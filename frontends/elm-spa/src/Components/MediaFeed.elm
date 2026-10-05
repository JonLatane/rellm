module Components.MediaFeed exposing
    ( Kind(..)
    , Model
    , Msg
    , creditsLine
    , init
    , mergeByRecency
    , requestFor
    , retryFetch
    , update
    , view
    )

{-| The server-wide media feeds behind `/video` (a YouTube-alike: a grid of thumbnail cards) and
`/audio` (an iTunes/Spotify-alike: a track list with cover art) -- both are just `GetMedia` with
no `user_id` (see `GetMediaRequest`'s own doc in `media.proto`) and a `content_type` wildcard
(`video/*`/`audio/*`), plus an optional `search_text`. Everything visibility-related (never other
users' private media, `LICENSED` media discoverable with only its preview playable) is enforced
server-side by `GetMedia`/`GET /media/{id}`.

Multi-server, like `Components.Pages.PostsPage`: one independent `GetMedia` feed per server enabled in
the Accounts Panel (`AccountsPanel.enabledServers`), each fetched as that server's signed-in account
if there is one (anonymously otherwise), merged newest-first (`mergeByRecency`). A server enabled
(or disabled) later is reconciled in by `retryFetch`, which the owning page calls on every
forwarded `Shared.Msg`. Tapping an item opens it in `Shared.MediaViewerPanel`, paging through every
loaded item _from that same server_ -- the viewer resolves media URLs/edit rights against a single
`targetHost` -- which is where playback and (for owners) editing happen.

Mounted by `Components.Pages.MediaPage`, which `Pages.Video`/`Pages.Audio`/`Pages.Media` all wrap.

-}

import Components.Authors as Authors
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, img, input, span, text)
import Html.Attributes exposing (attribute, class, disabled, href, placeholder, src, type_, value)
import Html.Events exposing (onClick, onInput)
import Process
import Proto.Rellm exposing (GetMediaRequest, GetMediaResponse, Media, MediaMetadata, defaultGetMediaRequest, defaultMediaMetadata)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (timestampToPosix)
import Shared.AudioPlayerPanel as AudioPlayerPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.Time as SharedTime
import Task
import Time
import Url
import UI.Classes exposing (classes, hostnameToCSSClass)


type Kind
    = Videos
    | Audio
    | Images


type alias Model =
    { kind : Kind
    , searchText : String

    -- Bumped by every `SearchChanged`; a response (or debounce timer) carrying an older value than
    -- this was superseded and is dropped.
    , searchVersion : Int

    -- One per enabled server, keyed by `frontendHost` -- see `retryFetch`.
    , feeds : Dict String HostFeed
    }


type alias HostFeed =
    { media : List Media
    , status : Status
    , hasNextPage : Bool
    , nextPage : Int
    , loadingMore : Bool

    -- Whether the first fetch has fired -- `Shared.AccountsPanel.init` seeds every persisted
    -- server disconnected until its own reconnect resolves (see
    -- `RellmServers.knownConnectedRellmServer`), so a feed can't always start fetching at once.
    , fetchStarted : Bool
    }


type Status
    = Loading
    | Loaded
    | Failed String


type Msg
    = GotMediaResult String Int Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
    | SearchChanged String
    | SearchDebounced Int
    | LoadMoreClicked
    | MediaClicked String String


init : Shared.Model -> Kind -> ( Model, Effect Msg )
init shared kind =
    retryFetch shared { kind = kind, searchText = "", searchVersion = 0, feeds = Dict.empty }


emptyHostFeed : HostFeed
emptyHostFeed =
    { media = [], status = Loading, hasNextPage = False, nextPage = 0, loadingMore = False, fetchStarted = False }


{-| `GetMedia` with no `user_id` -- the server-wide listing -- for `kind`'s content type, narrowed by
`searchText` (blank means no search). Pure so it's unit-testable.
-}
requestFor : Kind -> String -> Int -> GetMediaRequest
requestFor kind searchText page =
    { defaultGetMediaRequest
        | contentType =
            Just
                (case kind of
                    Videos ->
                        "video/*"

                    Audio ->
                        "audio/*"

                    Images ->
                        "image/*"
                )
        , searchText =
            if String.isEmpty (String.trim searchText) then
                Nothing

            else
                Just (String.trim searchText)
        , page = page
    }


{-| Every loaded `( host, media )` across servers, newest first (stable for equal timestamps, so
the order within one server's own response is kept). Pure so it's unit-testable.
-}
mergeByRecency : List ( String, Media ) -> List ( String, Media )
mergeByRecency items =
    List.sortBy (\( _, media ) -> negate (createdMillis media)) items


createdMillis : Media -> Int
createdMillis media =
    media.createdAt
        |> Maybe.map (\ts -> Time.posixToMillis (timestampToPosix ts))
        |> Maybe.withDefault 0


{-| Reconciles `model.feeds` with the servers currently enabled in the Accounts Panel (adding a
feed for a newly-enabled one, dropping a disabled one's), then starts the first fetch of any feed
whose server is connected by now. Safe to call repeatedly -- each feed fetches at most once from
here (`HostFeed.fetchStarted`) -- the owning page calls it on every `Shared.Msg` it's forwarded (a
server connecting or being enabled being the cue), same pattern as
`Components.Pages.MarketPage.attemptFetches`.
-}
retryFetch : Shared.Model -> Model -> ( Model, Effect Msg )
retryFetch shared model =
    let
        hosts : List String
        hosts =
            AccountsPanel.enabledServers shared.accounts |> List.map .frontendHost

        reconciled : Dict String HostFeed
        reconciled =
            hosts
                |> List.map (\host -> ( host, Dict.get host model.feeds |> Maybe.withDefault emptyHostFeed ))
                |> Dict.fromList

        step : String -> ( Dict String HostFeed, List (Effect Msg) ) -> ( Dict String HostFeed, List (Effect Msg) )
        step host ( soFar, effects ) =
            case Dict.get host soFar of
                Just feed ->
                    if not feed.fetchStarted && RellmServers.knownConnectedRellmServer shared.accounts.servers host /= Nothing then
                        ( Dict.insert host { feed | fetchStarted = True } soFar
                        , fetch shared model host model.searchVersion 0 :: effects
                        )

                    else
                        ( soFar, effects )

                Nothing ->
                    ( soFar, effects )

        ( updatedFeeds, fetchEffects ) =
            List.foldl step ( reconciled, [] ) hosts
    in
    ( { model | feeds = updatedFeeds }, Effect.batch fetchEffects )


fetch : Shared.Model -> Model -> String -> Int -> Int -> Effect Msg
fetch shared model host version page =
    AccountsPanel.performWithOptionalAccountServer
        shared.accounts
        ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId, host )
        (\server maybeToken ->
            Grpc.new Rellm.getMedia (requestFor model.kind model.searchText page)
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )
        |> Task.attempt (GotMediaResult host version page)
        |> Effect.fromCmd


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotMediaResult host version page result ->
            if version /= model.searchVersion then
                ( model, Effect.none )

            else
                case ( result, Dict.get host model.feeds ) of
                    ( Ok ( maybeAccountsPanelMsg, response ), Just feed ) ->
                        ( { model
                            | feeds =
                                Dict.insert host
                                    { feed
                                        | media =
                                            if page == 0 then
                                                response.media

                                            else
                                                feed.media ++ response.media
                                        , status = Loaded
                                        , hasNextPage = response.hasNextPage
                                        , nextPage = page + 1
                                        , loadingMore = False
                                    }
                                    model.feeds
                          }
                        , maybeAccountsPanelMsg
                            |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                            |> Maybe.withDefault Effect.none
                        )

                    ( Err err, Just feed ) ->
                        ( { model | feeds = Dict.insert host { feed | status = Failed (AccountsPanel.grpcErrorToString err), loadingMore = False } model.feeds }
                        , Effect.none
                        )

                    ( _, Nothing ) ->
                        ( model, Effect.none )

        SearchChanged text ->
            let
                version : Int
                version =
                    model.searchVersion + 1
            in
            ( { model | searchText = text, searchVersion = version }
            , Process.sleep 300 |> Task.perform (\_ -> SearchDebounced version) |> Effect.fromCmd
            )

        SearchDebounced version ->
            if version /= model.searchVersion then
                ( model, Effect.none )

            else
                -- Keeps showing the old results (rather than blanking to "Loading…") until the new ones land.
                ( model
                , model.feeds
                    |> Dict.toList
                    |> List.filter (\( _, feed ) -> feed.fetchStarted)
                    |> List.map (\( host, _ ) -> fetch shared model host version 0)
                    |> Effect.batch
                )

        LoadMoreClicked ->
            ( { model
                | feeds =
                    Dict.map
                        (\_ feed ->
                            if feed.hasNextPage then
                                { feed | loadingMore = True }

                            else
                                feed
                        )
                        model.feeds
              }
            , model.feeds
                |> Dict.toList
                |> List.filter (\( _, feed ) -> feed.hasNextPage)
                |> List.map (\( host, feed ) -> fetch shared model host model.searchVersion feed.nextPage)
                |> Effect.batch
            )

        MediaClicked host mediaId ->
            ( model
            , Effect.fromShared
                (if model.kind == Audio then
                    -- Audio plays in the persistent bottom player, queueing the tracks listed here.
                    Shared.AudioPlayerPanelMsg
                        (AudioPlayerPanel.Open
                            (Dict.get host model.feeds
                                |> Maybe.map .media
                                |> Maybe.withDefault []
                                |> List.map MediaViewerPanel.mediaToReference
                            )
                            mediaId
                            host
                        )

                 else
                    Shared.MediaViewerPanelMsg
                        (MediaViewerPanel.Open
                            (Dict.get host model.feeds
                                |> Maybe.map .media
                                |> Maybe.withDefault []
                                |> List.map MediaViewerPanel.mediaToReference
                            )
                            Nothing
                            mediaId
                            host
                        )
                )
            )



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    let
        items : List ( String, Media )
        items =
            model.feeds
                |> Dict.toList
                |> List.concatMap (\( host, feed ) -> List.map (Tuple.pair host) feed.media)
                |> mergeByRecency

        showHost : Bool
        showHost =
            Dict.size model.feeds > 1

        errors : List (Html Msg)
        errors =
            model.feeds
                |> Dict.toList
                |> List.filterMap
                    (\( host, feed ) ->
                        case feed.status of
                            Failed err ->
                                Just (div [ class "media-feed-message media-feed-error" ] [ text (host ++ ": " ++ (Url.percentDecode err |> Maybe.withDefault err)) ])

                            _ ->
                                Nothing
                    )

        card : ( String, Media ) -> Html Msg
        card ( host, media ) =
            let
                maybeServer : Maybe RellmServer
                maybeServer =
                    RellmServers.rellmServerForHost shared.accounts.servers host
            in
            case model.kind of
                Videos ->
                    videoCard shared showHost host maybeServer media

                Audio ->
                    audioRow shared showHost host maybeServer media

                Images ->
                    imageTile shared showHost host maybeServer media
    in
    div [ class "media-feed", class (kindClass model.kind) ]
        [ div [ class "media-feed-search" ]
            [ input
                [ type_ "search"
                , class "media-feed-search-input"
                , placeholder
                    (case model.kind of
                        Videos ->
                            "Search videos"

                        Audio ->
                            "Search audio"

                        Images ->
                            "Search images"
                    )
                , value model.searchText
                , onInput SearchChanged
                , attribute "aria-label" "Search"
                ]
                []
            ]
        , div [ class "media-feed-errors" ] errors
        , if not (List.isEmpty items) then
            div [ class "media-feed-items" ] (List.map card items)

          else
            let
                anyLoading : Bool
                anyLoading =
                    model.feeds |> Dict.values |> List.any (\feed -> feed.status == Loading)
            in
            if anyLoading then
                div [ class "media-feed-message" ] [ text "Loading…" ]

            else if List.isEmpty errors then
                let
                    emptyMessage : String
                    emptyMessage =
                        if Dict.isEmpty model.feeds then
                            "No servers are enabled."

                        else if String.isEmpty (String.trim model.searchText) then
                            case model.kind of
                                Videos ->
                                    "No videos yet."

                                Audio ->
                                    "No audio yet."

                                Images ->
                                    "No images yet."

                        else
                            "Nothing matches your search."
                in
                div [ class "media-feed-message" ] [ text emptyMessage ]

            else
                text ""
        , if model.feeds |> Dict.values |> List.any .hasNextPage then
            let
                loadingMore : Bool
                loadingMore =
                    model.feeds |> Dict.values |> List.any .loadingMore
            in
            button [ class "media-feed-load-more", onClick LoadMoreClicked, disabled loadingMore ]
                [ text
                    (if loadingMore then
                        "Loading…"

                     else
                        "Load more"
                    )
                ]

          else
            text ""
        ]


kindClass : Kind -> String
kindClass kind =
    case kind of
        Videos ->
            "media-feed-videos"

        Audio ->
            "media-feed-audio"

        Images ->
            "media-feed-images"


{-| The thumbnail `<img>` for `media` -- for video/audio only if the server has actually generated one (see
`MediaConversion`), since without it `GET /media/{id}?size=...` would fall back to serving the
whole video/audio file. `Nothing` otherwise (an unprocessed upload), and `view` shows a placeholder.
-}
thumbnailUrl : Kind -> Maybe RellmServer -> Media -> Maybe String
thumbnailUrl kind maybeServer media =
    let
        withSize : String -> Maybe String
        withSize sizeParam =
            maybeServer
                |> Maybe.andThen (\server -> RellmServers.mediaUrl server media.id)
                |> Maybe.map (\url -> url ++ "?size=" ++ sizeParam)

        ifGenerated : MediaConversion -> String -> Maybe String
        ifGenerated conversion sizeParam =
            if List.any (\size -> size.conversion == conversion) media.sizes then
                withSize sizeParam

            else
                Nothing
    in
    case kind of
        Videos ->
            ifGenerated VIDEOPREVIEWTHUMBNAILMEDIUM "video_preview_medium"

        Audio ->
            -- The cover art picked for the track, else what's embedded in the file, else the waveform.
            case media.metadata |> Maybe.andThen .coverArtMediaId of
                Just coverArtId ->
                    maybeServer
                        |> Maybe.andThen (\server -> RellmServers.mediaUrl server coverArtId)
                        |> Maybe.map (\url -> url ++ "?size=small")

                Nothing ->
                    case ifGenerated AUDIOCOVERARTSMALL "audio_cover_art_small" of
                        Just coverArt ->
                            Just coverArt

                        Nothing ->
                            ifGenerated AUDIOPREVIEWTHUMBNAILSMALL "audio_preview_small"

        -- Images are their own thumbnails: `size=medium` falls back to the original when the
        -- image is already small enough that no resized copy was generated.
        Images ->
            withSize "medium"


mediaTitle : Media -> String
mediaTitle media =
    case media.name of
        Just name ->
            if String.isEmpty (String.trim name) then
                "Untitled"

            else
                name

        Nothing ->
            "Untitled"


authorName : Media -> Maybe String
authorName media =
    media.author
        |> Maybe.andThen
            (\author ->
                case ( author.realName, author.username ) of
                    ( Just realName, _ ) ->
                        if String.isEmpty (String.trim realName) then
                            author.username

                        else
                            Just realName

                    ( Nothing, username ) ->
                        username
            )


authorLink : Shared.Model -> String -> Media -> Html msg
authorLink shared host media =
    authorLinkWith shared host Nothing False media


{-| `authorLink` with the author's small avatar (or initial-letter placeholder) in front of their
name -- audio/video rows, where there's room for it.
-}
authorLinkWithAvatar : Shared.Model -> String -> Maybe RellmServer -> Media -> Html msg
authorLinkWithAvatar shared host maybeServer media =
    authorLinkWith shared host maybeServer True media


authorLinkWith : Shared.Model -> String -> Maybe RellmServer -> Bool -> Media -> Html msg
authorLinkWith shared host maybeServer withAvatar media =
    let
        contents : String -> List (Html msg)
        contents name =
            if withAvatar then
                [ Authors.avatar name (Authors.avatarUrl maybeServer Nothing media.author), text name ]

            else
                [ text name ]

        authorClass : String
        authorClass =
            if withAvatar then
                "media-card-author media-card-author-with-avatar"

            else
                "media-card-author"
    in
    case ( authorName media, media.author |> Maybe.andThen .username ) of
        ( Just name, Just username ) ->
            a [ class authorClass, href (Users.usernameHref shared.basePath shared.accounts.mainFrontendHost host username) ] (contents name)

        ( Just name, Nothing ) ->
            span [ class authorClass ] (contents name)

        _ ->
            text ""


licensedBadge : Media -> Html msg
licensedBadge media =
    if media.visibility == LICENSED then
        span [ class "media-card-badge", attribute "title" "Full quality requires a license; previews are free." ] [ text "Licensed" ]

    else
        text ""


createdLabel : Shared.Model -> Media -> String
createdLabel shared media =
    media.createdAt
        |> Maybe.map (\ts -> SharedTime.formatDate shared.time.browserTimeZone.zone (timestampToPosix ts))
        |> Maybe.withDefault ""


{-| The credits worth surfacing on a card, in the order they appear in `MediaMetadata` -- for audio
"Artist · Album", for video "Director · Starring". Empty if none are set. Pure so it's unit-testable.
-}
creditsLine : Kind -> MediaMetadata -> String
creditsLine kind metadata =
    (case kind of
        Audio ->
            [ metadata.artist, metadata.album ]

        Videos ->
            [ metadata.director, metadata.starring ]

        Images ->
            []
    )
        |> List.filterMap (Maybe.andThen nonBlank)
        |> String.join " · "


nonBlank : String -> Maybe String
nonBlank s =
    if String.isEmpty (String.trim s) then
        Nothing

    else
        Just (String.trim s)


videoCard : Shared.Model -> Bool -> String -> Maybe RellmServer -> Media -> Html Msg
videoCard shared showHost host maybeServer media =
    let
        credits : String
        credits =
            creditsLine Videos (Maybe.withDefault defaultMediaMetadata media.metadata)
    in
    div [ class "media-card video-card" ]
        [ button [ class "media-card-thumb", onClick (MediaClicked host media.id), attribute "aria-label" ("Play " ++ mediaTitle media) ]
            [ case thumbnailUrl Videos maybeServer media of
                Just url ->
                    img [ src url, attribute "alt" "", attribute "loading" "lazy" ] []

                Nothing ->
                    span [ class "media-card-thumb-placeholder" ] [ text "🎬" ]
            , span [ class "media-card-play" ] [ text "▶" ]
            , licensedBadge media
            ]
        , div [ class "media-card-meta" ]
            [ button [ class "media-card-title", onClick (MediaClicked host media.id) ] [ text (mediaTitle media) ]
            , div [ class "media-card-sub" ]
                [ authorLinkWithAvatar shared host maybeServer media
                , span [ class "media-card-date" ] [ text (createdLabel shared media) ]
                ]
            , hostBadge showHost host
            , if String.isEmpty credits then
                text ""

              else
                div [ class "media-card-credits" ] [ text credits ]
            ]
        ]


audioRow : Shared.Model -> Bool -> String -> Maybe RellmServer -> Media -> Html Msg
audioRow shared showHost host maybeServer media =
    let
        credits : String
        credits =
            creditsLine Audio (Maybe.withDefault defaultMediaMetadata media.metadata)

        -- `Just playing` for the track the persistent audio player has loaded (`playing` = actually
        -- playing vs. paused), `Nothing` for every other row.
        nowPlaying : Maybe Bool
        nowPlaying =
            let
                player : AudioPlayerPanel.Model
                player =
                    shared.panels.audioPlayerPanel
            in
            if player.currentId == Just media.id && player.targetHost == host then
                Just player.playing

            else
                Nothing
    in
    div
        [ classes
            ("media-card"
                :: "audio-row"
                :: (case nowPlaying of
                        Just True ->
                            [ "is-now-playing", "is-playing" ]

                        Just False ->
                            [ "is-now-playing" ]

                        Nothing ->
                            []
                   )
            )
        ]
        [ button [ class "media-card-thumb", onClick (MediaClicked host media.id), attribute "aria-label" ("Play " ++ mediaTitle media) ]
            [ case thumbnailUrl Audio maybeServer media of
                Just url ->
                    img [ src url, attribute "alt" "", attribute "loading" "lazy" ] []

                Nothing ->
                    span [ class "media-card-thumb-placeholder" ] [ text "🎵" ]
            , case nowPlaying of
                -- A live equalizer over the cover (bars bounce while playing, rest flat when paused).
                Just playing ->
                    span
                        [ class "media-card-now-playing"
                        , attribute "role" "img"
                        , attribute "aria-label"
                            (if playing then
                                "Now playing"

                             else
                                "Paused"
                            )
                        ]
                        [ span [] [], span [] [], span [] [], span [] [] ]

                Nothing ->
                    span [ class "media-card-play" ] [ text "▶" ]
            ]
        , div [ class "media-card-meta" ]
            [ button [ class "media-card-title", onClick (MediaClicked host media.id) ] [ text (mediaTitle media) ]
            , if String.isEmpty credits then
                text ""

              else
                div [ class "media-card-credits" ] [ text credits ]
            , -- The server badge sits beside the author (wrapping with the line on narrow screens) rather
              -- than as a column of its own at the row's right edge.
              div [ class "media-card-sub" ]
                [ authorLinkWithAvatar shared host maybeServer media
                , hostBadge showHost host
                , span [ class "media-card-date" ] [ text (createdLabel shared media) ]
                ]
            ]
        , licensedBadge media
        ]


{-| The server a card came from, shown only when more than one server's feed is being merged -- in
that server's own colors, like the federated-profile chips.
-}
hostBadge : Bool -> String -> Html msg
hostBadge showHost host =
    if showHost then
        span [ classes [ "media-card-host", hostnameToCSSClass host, "background-color-primary" ] ] [ text host ]

    else
        text ""


{-| A photo-gallery tile: the image itself, cropped to a square, with its title/author/server on
hover (always shown on touch devices -- see `.image-tile-caption` in media\_pages.css).
-}
imageTile : Shared.Model -> Bool -> String -> Maybe RellmServer -> Media -> Html Msg
imageTile shared showHost host maybeServer media =
    div [ class "media-card image-tile" ]
        [ button [ class "media-card-thumb", onClick (MediaClicked host media.id), attribute "aria-label" ("View " ++ mediaTitle media) ]
            [ case thumbnailUrl Images maybeServer media of
                Just url ->
                    img [ src url, attribute "alt" (mediaTitle media), attribute "loading" "lazy" ] []

                Nothing ->
                    span [ class "media-card-thumb-placeholder" ] [ text "🖼️" ]
            , licensedBadge media
            ]
        , div [ class "image-tile-caption" ]
            [ span [ class "media-card-title-text" ] [ text (mediaTitle media) ]
            , div [ class "media-card-sub" ] [ authorLink shared host media, hostBadge showHost host ]
            ]
        ]
