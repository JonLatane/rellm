module Components.MediaFeed exposing
    ( Kind(..)
    , Model
    , Msg
    , applyEdit
    , creditsLine
    , init
    , mergeByRecency
    , replaceMedia
    , requestFor
    , retryFetch
    , syncMsg
    , clearMsg
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

Videos and audio also come from Mastodon and Bluesky, as _posts_ that carry them (`Shared.Federation.Media`):
one feed per Mastodon instance / Bluesky source the Accounts Panel has enabled (`federatedSources`), searched
with the same box (a Bluesky text search; a Mastodon hashtag) and merged with the Rellm servers' media
newest-first. They play through the same viewer/audio player as a post's own media does.

What's on screen is registered with the Countabilibar (`syncMsg`: videos / tracks per server and author, whose
checkboxes hide servers and authors here too).

Mounted by `Components.Pages.MediaPage`, which `Pages.Video`/`Pages.Audio`/`Pages.Media` all wrap.

-}

import Components.Authors as Authors
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, img, input, span, text)
import Html.Attributes exposing (attribute, class, disabled, href, placeholder, src, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Process
import Proto.Rellm exposing (Author, GetMediaRequest, GetMediaResponse, Media, MediaMetadata, MediaReference, Post, defaultGetMediaRequest, defaultMediaMetadata)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared
import Http
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.Countabilibar as Countabilibar
import Shared.Federation.Actions as Actions
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Common exposing (BlueskyAuth, anonymousSearchHost, blueskyAuthFor)
import Shared.Federation.Mastodon as Mastodon
import Shared.Federation.Media as FedMedia
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (timestampToPosix)
import Shared.AudioPlayerPanel as AudioPlayerPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.Time as SharedTime
import Task
import Time
import UI.Glyph as Glyph
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

    -- One per Mastodon instance / Bluesky source whose posts are searched for video/audio (always empty for
    -- `Images`), keyed by its `"mastodon:"`/`"bluesky:"`-tagged host -- see `federatedSources`.
    , federated : Dict String FedFeed

    -- Bumped after every add-to-queue pick, which re-creates the rows' hidden `<select>`s (see
    -- `queueButton`) so they're blank again.
    , queueGeneration : Int
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

    -- The account (`Nothing` = anonymous) acting on the server when the feed was last fetched -- what
    -- `GetMedia` returns depends on it (a signed-in viewer can also see `SERVER_PUBLIC` media), so
    -- `retryFetch` refetches the first page when it changes, and a reply made as another account
    -- is dropped. See `retryFetch`.
    , fetchedAs : Maybe String
    }


type Status
    = Loading
    | Loaded
    | Failed String


{-| What one Mastodon/Bluesky source has handed over so far. `next` is the cursor for its next page
(`Nothing` once it has run out); `requestId` stamps the newest fetch, so an older response is dropped.
-}
type alias FedFeed =
    { items : List FedMedia.Item
    , status : Status
    , next : Maybe String
    , loadingMore : Bool
    , fetchStarted : Bool
    , requestId : Int
    }


emptyFedFeed : FedFeed
emptyFedFeed =
    { items = [], status = Loading, next = Nothing, loadingMore = False, fetchStarted = False, requestId = 0 }


{-| A federated place to look for video/audio posts.
-}
type FedSource
    = FedMastodon String
    | FedBlueskyAccount BlueskyAccount
    | FedBlueskyAppView String


{-| One thing listed: a Rellm server's media item (with that server's host), or a video/audio from a
Mastodon/Bluesky post.
-}
type Entry
    = RellmEntry String Media
    | FedEntry FedMedia.Item


entryMillis : Entry -> Int
entryMillis entry =
    case entry of
        RellmEntry _ media ->
            createdMillis media

        FedEntry item ->
            item.post.createdAt
                |> Maybe.map (\ts -> Time.posixToMillis (timestampToPosix ts))
                |> Maybe.withDefault 0


fedKey : FedSource -> String
fedKey source =
    case source of
        FedMastodon host ->
            "mastodon:" ++ host

        FedBlueskyAccount account ->
            "bluesky:" ++ account.handle

        FedBlueskyAppView host ->
            "bluesky:" ++ host


{-| Every Mastodon instance (connected, or browsed and enabled) and Bluesky account/AppView in use, for the
Video and Audio feeds -- never for Images (neither network has a media library, and a photo feed isn't
asked for), and Bluesky only for Videos (it has no audio).
-}
federatedSources : Shared.Model -> Kind -> List FedSource
federatedSources shared kind =
    if kind == Images then
        []

    else
        (List.map .instanceHost shared.accounts.mastodonAccounts
            ++ (shared.accounts.browsedMastodonInstances |> List.filter .enabled |> List.map .host)
            |> Set.fromList
            |> Set.toList
            |> List.map FedMastodon
        )
            ++ (if kind == Videos then
                    -- (Bluesky has video but no audio, so the Audio page has nothing to look for there.)
                    List.map FedBlueskyAccount (List.filter .enabled shared.accounts.blueskyAccounts)
                        ++ List.map (.host >> FedBlueskyAppView) (List.filter .enabled shared.accounts.blueskyAppViews)

                else
                    []
               )


type Msg
    = GotMediaResult String (Maybe String) Int Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
    | SearchChanged String
    | SearchDebounced Int
    | LoadMoreClicked
    | MediaClicked String String
    | GotFederated String Int Bool (Result Http.Error ( Maybe AccountsPanel.Msg, List FedMedia.Item, Maybe String ))
    | FedMediaClicked String String
    | FedQueuePicked String String String
      -- host, media id, picked `<option>` value ("next" or "last")
    | QueuePicked String String String


{-| `searchText` seeds the search box (and the first fetch) -- e.g. from a `?search_text=` URL parameter; blank
for none.
-}
init : Shared.Model -> Kind -> String -> ( Model, Effect Msg )
init shared kind searchText =
    retryFetch shared { kind = kind, searchText = searchText, searchVersion = 0, feeds = Dict.empty, federated = Dict.empty, queueGeneration = 0 }


emptyHostFeed : HostFeed
emptyHostFeed =
    { media = [], status = Loading, hasNextPage = False, nextPage = 0, loadingMore = False, fetchStarted = False, fetchedAs = Nothing }


{-| A media item saved from the viewer (`Shared.MediaViewerPanel`'s edit form) while this feed is showing it: the feed for
`host` (the server the viewer was on) swaps in the saved copy, so the title, credits and description on screen are the new ones
without refetching (which would also lose the user's scroll and loaded pages).
-}
applyEdit : String -> Media -> Model -> Model
applyEdit host updated model =
    { model
        | feeds = Dict.update host (Maybe.map (\feed -> { feed | media = replaceMedia updated feed.media })) model.feeds
    }


{-| `updated` in place of the item with its id, if the list has one (same order, same length).
-}
replaceMedia : Media -> List Media -> List Media
replaceMedia updated =
    List.map
        (\media ->
            if media.id == updated.id then
                updated

            else
                media
        )


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
`Components.Pages.MarketPage.attemptFetches`. A feed that's already fetched is fetched again (first
page, the old media staying on screen meanwhile) when the account acting on its server changes --
signing in or out, or enabling/disabling an account -- since the listing depends on who's asking.
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
                    if RellmServers.knownConnectedRellmServer shared.accounts.servers host == Nothing then
                        ( soFar, effects )

                    else if not feed.fetchStarted || actingAccountId shared host /= feed.fetchedAs then
                        -- The paging state (`nextPage`/`hasNextPage`/`loadingMore`) belongs to the previous
                        -- account's listing, so it's reset: "Load more" must stay unavailable until this
                        -- first page lands, or it would request one of the *previous* account's page numbers
                        -- as the new account, and whichever reply came second would skip the pages between.
                        -- (The old media stays on screen meanwhile.)
                        ( Dict.insert host
                            { feed
                                | fetchStarted = True
                                , fetchedAs = actingAccountId shared host
                                , hasNextPage = False
                                , nextPage = 0
                                , loadingMore = False
                            }
                            soFar
                        , fetch shared model host model.searchVersion 0 :: effects
                        )

                    else
                        ( soFar, effects )

                Nothing ->
                    ( soFar, effects )

        ( updatedFeeds, fetchEffects ) =
            List.foldl step ( reconciled, [] ) hosts

        sources : List FedSource
        sources =
            federatedSources shared model.kind

        fedReconciled : Dict String FedFeed
        fedReconciled =
            sources
                |> List.map (\source -> ( fedKey source, Dict.get (fedKey source) model.federated |> Maybe.withDefault emptyFedFeed ))
                |> Dict.fromList

        fedStep : FedSource -> ( Dict String FedFeed, List (Effect Msg) ) -> ( Dict String FedFeed, List (Effect Msg) )
        fedStep source ( soFar, effects ) =
            case Dict.get (fedKey source) soFar of
                Just feed ->
                    if feed.fetchStarted then
                        ( soFar, effects )

                    else
                        ( Dict.insert (fedKey source) { feed | fetchStarted = True, requestId = feed.requestId + 1 } soFar
                        , fetchFederated model source (feed.requestId + 1) Nothing False :: effects
                        )

                Nothing ->
                    ( soFar, effects )

        ( fedFeeds, fedEffects ) =
            List.foldl fedStep ( fedReconciled, [] ) sources
    in
    ( { model | feeds = updatedFeeds, federated = fedFeeds }, Effect.batch (fetchEffects ++ fedEffects) )


{-| The id of the account currently acting on `host` (the enabled one), `Nothing` when anonymous.
-}
actingAccountId : Shared.Model -> String -> Maybe String
actingAccountId shared host =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId


fetch : Shared.Model -> Model -> String -> Int -> Int -> Effect Msg
fetch shared model host version page =
    AccountsPanel.performWithOptionalAccountServer
        shared.accounts
        ( actingAccountId shared host, host )
        (\server maybeToken ->
            Grpc.new Rellm.getMedia (requestFor model.kind model.searchText page)
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )
        |> Task.attempt (GotMediaResult host (actingAccountId shared host) version page)
        |> Effect.fromCmd


{-| Fetches a page of video/audio posts from one federated source. `cursor` is `Nothing` for the first page
(or a fresh search); `append` says whether the result extends what's shown. `requestId` is the feed's newest
(see `FedFeed.requestId`). The task resolves to the `AccountsPanel.Msg` to forward if a Bluesky account's token
had to be refreshed on the way.
-}
fetchFederated : Model -> FedSource -> Int -> Maybe String -> Bool -> Effect Msg
fetchFederated model source requestId cursor append =
    let
        key : String
        key =
            fedKey source

        kind : FedMedia.Kind
        kind =
            if model.kind == Audio then
                FedMedia.AudioKind

            else
                FedMedia.VideoKind

        search : String
        search =
            String.trim model.searchText

        -- Without a search it reads Bluesky's "What's Hot" feed: about one post in ten there has a video, where the
        -- newest posts (`Bluesky.fetchLatestPosts`) have one in fifty or fewer, so a few pages of those often held
        -- none at all. With a search it's the network-wide search, which needs its own host for an AppView.
        blueskyPage : { feedAuth : BlueskyAuth, searchAuth : BlueskyAuth } -> Maybe String -> Task.Task Http.Error ( List Post, Maybe String )
        blueskyPage { feedAuth, searchAuth } page =
            if String.isEmpty search then
                Bluesky.fetchWhatsHot feedAuth page

            else
                Bluesky.searchPosts Bluesky.SearchTop Nothing searchAuth search page

        task : Task.Task Http.Error ( Maybe AccountsPanel.Msg, List FedMedia.Item, Maybe String )
        task =
            case source of
                FedMastodon host ->
                    FedMedia.collect kind key (Mastodon.fetchMediaPosts host search) cursor
                        |> Task.map (\( items, next ) -> ( Nothing, items, next ))

                FedBlueskyAccount account ->
                    BlueskyAccounts.performWithBlueskyAccount account (\auth -> FedMedia.collect kind key (blueskyPage { feedAuth = auth, searchAuth = auth }) cursor)
                        |> Task.map (\( refreshed, ( items, next ) ) -> ( Actions.rotatedBluesky account refreshed, items, next ))

                FedBlueskyAppView host ->
                    FedMedia.collect kind key (blueskyPage { feedAuth = blueskyAuthFor host, searchAuth = blueskyAuthFor (anonymousSearchHost host) }) cursor
                        |> Task.map (\( items, next ) -> ( Nothing, items, next ))
    in
    task
        |> Task.attempt (GotFederated key requestId append)
        |> Effect.fromCmd


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotMediaResult host fetchedAs version page result ->
            if version /= model.searchVersion || Just fetchedAs /= (Dict.get host model.feeds |> Maybe.map .fetchedAs) then
                -- Stale: for an older search, or made as an account that's no longer the acting one
                -- (what it returned is what the *previous* account could see; `retryFetch` has
                -- already started a fetch as the current one). The page data is dropped, but its
                -- token refresh isn't: a refresh can rotate the account's refresh token, so losing
                -- the new one could force a re-login.
                ( model
                , AccountsPanel.tokenRefreshOf result
                    |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                    |> Maybe.withDefault Effect.none
                )

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

        GotFederated key requestId append result ->
            let
                forwardRefresh : Effect Msg
                forwardRefresh =
                    case result of
                        Ok ( maybeAccountsPanelMsg, _, _ ) ->
                            maybeAccountsPanelMsg
                                |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                                |> Maybe.withDefault Effect.none

                        Err _ ->
                            Effect.none
            in
            case Dict.get key model.federated of
                Just feed ->
                    if requestId /= feed.requestId then
                        -- Superseded by a newer search/page request. The page is dropped, but a token refresh isn't.
                        ( model, forwardRefresh )

                    else
                        case result of
                            Ok ( _, items, next ) ->
                                ( { model
                                    | federated =
                                        Dict.insert key
                                            { feed
                                                | items =
                                                    if append then
                                                        feed.items ++ List.filter (\item -> not (List.any (\existing -> existing.id == item.id) feed.items)) items

                                                    else
                                                        items
                                                , status = Loaded
                                                , next = next
                                                , loadingMore = False
                                            }
                                            model.federated
                                  }
                                , forwardRefresh
                                )

                            Err err ->
                                ( { model | federated = Dict.insert key { feed | status = Failed (httpErrorText err), loadingMore = False } model.federated }
                                , Effect.none
                                )

                Nothing ->
                    ( model, forwardRefresh )

        FedMediaClicked key mediaId ->
            let
                items : List FedMedia.Item
                items =
                    Dict.get key model.federated
                        |> Maybe.map .items
                        |> Maybe.withDefault []

                -- Where each item's post is in the Rellm UI: the viewer's "View post" button, and the audio
                -- player's "Opened from post" link, go there.
                postLinks : Dict String String
                postLinks =
                    items
                        |> List.map (\item -> ( item.media.id, Posts.postHref shared.basePath shared.accounts.mainFrontendHost item.host item.post ))
                        |> Dict.fromList

                references : List MediaReference
                references =
                    List.map .media items
            in
            ( model
            , if model.kind == Audio then
                Effect.batch
                    (Effect.fromShared (Shared.AudioPlayerPanelMsg (AudioPlayerPanel.Open references mediaId key))
                        :: (postLinks
                                |> Dict.toList
                                |> List.map (\( id, link ) -> Effect.fromShared (Shared.AudioPlayerPanelMsg (AudioPlayerPanel.AttachPostUrl id key (Just link))))
                           )
                    )

              else
                Effect.fromShared (Shared.MediaViewerPanelMsg (MediaViewerPanel.OpenWithPostLinks references postLinks mediaId key))
            )

        FedQueuePicked key mediaId choice ->
            ( { model | queueGeneration = model.queueGeneration + 1 }
            , case Dict.get key model.federated |> Maybe.andThen (\feed -> feed.items |> List.filter (\item -> item.media.id == mediaId) |> List.head) of
                Just item ->
                    Effect.fromShared
                        (Shared.AudioPlayerPanelMsg
                            (AudioPlayerPanel.Enqueue
                                (if choice == "next" then
                                    AudioPlayerPanel.PlayNext

                                 else
                                    AudioPlayerPanel.PlayLast
                                )
                                item.media
                                key
                            )
                        )

                Nothing ->
                    Effect.none
            )

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
                let
                    ( fedFeeds, fedEffects ) =
                        refetchFederated shared model
                in
                ( { model | federated = fedFeeds }
                , Effect.batch
                    (fedEffects
                        :: (model.feeds
                                |> Dict.toList
                                |> List.filter (\( _, feed ) -> feed.fetchStarted)
                                |> List.map (\( host, _ ) -> fetch shared model host version 0)
                           )
                    )
                )

        LoadMoreClicked ->
            let
                step : FedSource -> ( Dict String FedFeed, List (Effect Msg) ) -> ( Dict String FedFeed, List (Effect Msg) )
                step source ( dict, effects ) =
                    case Dict.get (fedKey source) dict of
                        Just feed ->
                            if feed.next /= Nothing && not feed.loadingMore then
                                ( Dict.insert (fedKey source) { feed | loadingMore = True, requestId = feed.requestId + 1 } dict
                                , fetchFederated model source (feed.requestId + 1) feed.next True :: effects
                                )

                            else
                                ( dict, effects )

                        Nothing ->
                            ( dict, effects )

                ( fedFeeds, fedEffects ) =
                    List.foldl step ( model.federated, [] ) (federatedSources shared model.kind)
            in
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
                , federated = fedFeeds
              }
            , Effect.batch
                (fedEffects
                    ++ (model.feeds
                            |> Dict.toList
                            |> List.filter (\( _, feed ) -> feed.hasNextPage)
                            |> List.map (\( host, feed ) -> fetch shared model host model.searchVersion feed.nextPage)
                       )
                )
            )

        QueuePicked host mediaId choice ->
            ( { model | queueGeneration = model.queueGeneration + 1 }
            , case Dict.get host model.feeds |> Maybe.andThen (\feed -> feed.media |> List.filter (\media -> media.id == mediaId) |> List.head) of
                Just media ->
                    Effect.fromShared
                        (Shared.AudioPlayerPanelMsg
                            (AudioPlayerPanel.Enqueue
                                (if choice == "next" then
                                    AudioPlayerPanel.PlayNext

                                 else
                                    AudioPlayerPanel.PlayLast
                                )
                                (MediaViewerPanel.mediaToReference media)
                                host
                            )
                        )

                Nothing ->
                    Effect.none
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



{-| Restarts every already-started federated feed from its first page for the current search, keeping what's
shown until the new results land.
-}
refetchFederated : Shared.Model -> Model -> ( Dict String FedFeed, Effect Msg )
refetchFederated shared model =
    let
        step : FedSource -> ( Dict String FedFeed, List (Effect Msg) ) -> ( Dict String FedFeed, List (Effect Msg) )
        step source ( dict, effects ) =
            case Dict.get (fedKey source) dict of
                Just feed ->
                    if feed.fetchStarted then
                        ( Dict.insert (fedKey source) { feed | requestId = feed.requestId + 1, loadingMore = False } dict
                        , fetchFederated model source (feed.requestId + 1) Nothing False :: effects
                        )

                    else
                        ( dict, effects )

                Nothing ->
                    ( dict, effects )
    in
    List.foldl step ( model.federated, [] ) (federatedSources shared model.kind)
        |> Tuple.mapSecond Effect.batch


httpErrorText : Http.Error -> String
httpErrorText err =
    case err of
        Http.BadStatus status ->
            "the server answered " ++ String.fromInt status

        Http.Timeout ->
            "it took too long to respond"

        _ ->
            "couldn't reach it"



-- COUNTABILIBAR


{-| The `Shared.Countabilibar` kind this feed's items count as: videos, or audio tracks. Images aren't counted.
-}
countKind : Kind -> Maybe Countabilibar.Kind
countKind kind =
    case kind of
        Videos ->
            Just Countabilibar.VideosKind

        Audio ->
            Just Countabilibar.TracksKind

        Images ->
            Nothing


{-| Everything the feed is showing -- the author and id of each item, by host -- the same set `view` lists
(loaded, and not hidden by an unchecked server or author in the Countabilibar). Items without an author can't be
counted.
-}
shownByHost : Shared.Model -> Model -> Dict String (List ( Author, String ))
shownByHost shared model =
    let
        state : Countabilibar.Hidden
        state =
            Countabilibar.hidden shared.countabilibar

        add : String -> Maybe Author -> String -> Dict String (List ( Author, String )) -> Dict String (List ( Author, String ))
        add host maybeAuthor id dict =
            case maybeAuthor of
                Just author ->
                    if Countabilibar.isAuthorHidden state host author.userId then
                        dict

                    else
                        Dict.update host (\existing -> Just (( author, id ) :: Maybe.withDefault [] existing)) dict

                Nothing ->
                    dict
    in
    Dict.foldl
        (\host feed dict ->
            if Countabilibar.isHostHidden state host then
                dict

            else
                List.foldl (\media -> add host media.author media.id) dict feed.media
        )
        Dict.empty
        model.feeds
        |> (\withRellm ->
                Dict.foldl
                    (\host feed dict ->
                        if Countabilibar.isHostHidden state host then
                            dict

                        else
                            List.foldl (\item -> add host item.post.author item.id) dict feed.items
                    )
                    withRellm
                    model.federated
           )


{-| Hosts still waiting on a fetch -- the Countabilibar leaves them alone until they land.
-}
pendingHosts : Model -> Set String
pendingHosts model =
    (Dict.toList model.feeds |> List.filter (\( _, feed ) -> feed.status == Loading || feed.loadingMore) |> List.map Tuple.first)
        ++ (Dict.toList model.federated |> List.filter (\( _, feed ) -> feed.status == Loading || feed.loadingMore) |> List.map Tuple.first)
        |> Set.fromList


{-| What to tell the Countabilibar after an update so it agrees with what this feed shows (`Nothing` when it
already does, or for a feed it doesn't count) -- see `Countabilibar.syncMsg`.
-}
syncMsg : Shared.Model -> Model -> Maybe Shared.Msg
syncMsg shared model =
    countKind model.kind
        |> Maybe.andThen (\kind -> Countabilibar.syncMsg kind (pendingHosts model) (shownByHost shared model) shared.countabilibar)
        |> Maybe.map Shared.CountabilibarSync


{-| For a feed that isn't on screen (another tab): forget everything it registered.
-}
clearMsg : Shared.Model -> Model -> Maybe Shared.Msg
clearMsg shared model =
    countKind model.kind
        |> Maybe.andThen (\kind -> Countabilibar.syncMsg kind Set.empty Dict.empty shared.countabilibar)
        |> Maybe.map Shared.CountabilibarSync



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    let
        hiddenState : Countabilibar.Hidden
        hiddenState =
            Countabilibar.hidden shared.countabilibar

        -- Whatever the Countabilibar has unchecked (a whole server, or one author on it) isn't listed.
        notHidden : String -> Maybe Author -> Bool
        notHidden host maybeAuthor =
            not (Countabilibar.isHostHidden hiddenState host)
                && (maybeAuthor |> Maybe.map (\author -> not (Countabilibar.isAuthorHidden hiddenState host author.userId)) |> Maybe.withDefault True)

        items : List Entry
        items =
            (model.feeds
                |> Dict.toList
                |> List.concatMap
                    (\( host, feed ) ->
                        feed.media
                            |> List.filter (\media -> notHidden host media.author)
                            |> List.map (RellmEntry host)
                    )
            )
                ++ (model.federated
                        |> Dict.toList
                        |> List.concatMap
                            (\( host, feed ) ->
                                feed.items
                                    |> List.filter (\item -> notHidden host item.post.author)
                                    |> List.map FedEntry
                            )
                   )
                |> List.sortBy (entryMillis >> negate)

        showHost : Bool
        showHost =
            Dict.size model.feeds + Dict.size model.federated > 1

        errors : List (Html Msg)
        errors =
            (model.feeds
                |> Dict.toList
                |> List.filterMap
                    (\( host, feed ) ->
                        case feed.status of
                            Failed err ->
                                Just (div [ class "media-feed-message media-feed-error" ] [ text (host ++ ": " ++ (Url.percentDecode err |> Maybe.withDefault err)) ])

                            _ ->
                                Nothing
                    )
            )
                ++ (model.federated
                        |> Dict.toList
                        |> List.filterMap
                            (\( host, feed ) ->
                                case feed.status of
                                    Failed err ->
                                        Just (div [ class "media-feed-message media-feed-error" ] [ text (host ++ ": " ++ err) ])

                                    _ ->
                                        Nothing
                            )
                   )

        card : Entry -> Html Msg
        card entry =
            case entry of
                FedEntry item ->
                    case model.kind of
                        Audio ->
                            fedAudioRow shared model.queueGeneration showHost item

                        _ ->
                            fedVideoCard shared showHost item

                RellmEntry host media ->
                    let
                        maybeServer : Maybe RellmServer
                        maybeServer =
                            RellmServers.rellmServerForHost shared.accounts.servers host
                    in
                    case model.kind of
                        Videos ->
                            videoCard shared showHost host maybeServer media

                        Audio ->
                            audioRow shared model.queueGeneration showHost host maybeServer media

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
                    (model.feeds |> Dict.values |> List.any (\feed -> feed.status == Loading))
                        || (model.federated |> Dict.values |> List.any (\feed -> feed.status == Loading))
            in
            if anyLoading then
                div [ class "media-feed-message" ] [ text "Loading…" ]

            else if List.isEmpty errors then
                let
                    emptyMessage : String
                    emptyMessage =
                        if Dict.isEmpty model.feeds && Dict.isEmpty model.federated then
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
        , if (model.feeds |> Dict.values |> List.any .hasNextPage) || (model.federated |> Dict.values |> List.any (\feed -> feed.next /= Nothing)) then
            let
                loadingMore : Bool
                loadingMore =
                    (model.feeds |> Dict.values |> List.any .loadingMore) || (model.federated |> Dict.values |> List.any .loadingMore)
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
            -- (Video cards draw theirs with `MediaRenderer.videoPosterUrl`/`posterFrame`.)
            Nothing

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
            (MediaRenderer.posterFrame "🎬"
                (MediaRenderer.videoPosterUrl maybeServer
                    (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host)
                    (MediaViewerPanel.mediaToReference media)
                )
                ++ [ licensedBadge media ]
            )
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


audioRow : Shared.Model -> Int -> Bool -> String -> Maybe RellmServer -> Media -> Html Msg
audioRow shared queueGeneration showHost host maybeServer media =
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
                    span [ class "media-card-play" ] [ text Glyph.play ]
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
        , queueButton queueGeneration host media
        ]


{-| The row's add-to-queue button: the queue glyph over a transparent native `<select>` that fills it, so
tapping opens the platform's own picker with the two choices (under a disabled "Queue" heading, which is what's
selected, so either choice fires `change`) -- re-created (`generation`) after each pick to reset to the heading.
(Only the Audio page's rows have this; the player's own queue rows don't.)
-}
queueButton : Int -> String -> Media -> Html Msg
queueButton generation host media =
    Html.Keyed.node "span"
        [ class "audio-row-queue" ]
        [ ( String.fromInt generation
          , span [ class "audio-row-queue-inner", attribute "title" "Add to queue" ]
                [ AudioPlayerPanel.queueIcon
                , Html.select
                    [ class "audio-row-queue-select"
                    , attribute "aria-label" ("Add " ++ mediaTitle media ++ " to queue")
                    , onInput (QueuePicked host media.id)
                    ]
                    [ -- A disabled, pre-selected heading: iOS's picker puts a checkmark on the selected option,
                      -- which would otherwise be the first real choice.
                      Html.option [ value "", Html.Attributes.disabled True, Html.Attributes.selected True ] [ text "Queue" ]
                    , Html.option [ value "next" ] [ text "Add Next In Queue" ]
                    , Html.option [ value "last" ] [ text "Add To Queue" ]
                    ]
                ]
          )
        ]


{-| What a Mastodon/Bluesky post's video/audio is called on a card: the attachment's own name (its alt text) if
it has one, else the start of the post's text, else a plain "Video"/"Audio".
-}
fedTitle : FedMedia.Item -> String
fedTitle item =
    case item.media.name |> Maybe.andThen nonBlank of
        Just name ->
            FedMedia.plainTitle 90 name

        Nothing ->
            case item.post.content |> Maybe.map (FedMedia.plainTitle 90) |> Maybe.andThen nonBlank of
                Just postText ->
                    postText

                Nothing ->
                    case item.kind of
                        FedMedia.VideoKind ->
                            "Video"

                        FedMedia.AudioKind ->
                            "Audio"


{-| The poster's name (linking to their profile), with their avatar when `withAvatar`.
-}
fedAuthorLink : Shared.Model -> Bool -> FedMedia.Item -> Html msg
fedAuthorLink shared withAvatar item =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            Posts.mediaServer Nothing item.host

        name : Maybe String
        name =
            item.post.author
                |> Maybe.andThen
                    (\author ->
                        case author.realName |> Maybe.andThen nonBlank of
                            Just realName ->
                                Just realName

                            Nothing ->
                                author.username
                    )

        authorClass : String
        authorClass =
            if withAvatar then
                "media-card-author media-card-author-with-avatar"

            else
                "media-card-author"

        contents : String -> List (Html msg)
        contents shown =
            if withAvatar then
                [ Authors.avatar shown (Authors.avatarUrl maybeServer Nothing item.post.author), text shown ]

            else
                [ text shown ]
    in
    case ( name, item.post.author |> Maybe.andThen .username ) of
        ( Just shown, Just username ) ->
            a [ class authorClass, href (Users.usernameHref shared.basePath shared.accounts.mainFrontendHost item.host username) ] (contents shown)

        ( Just shown, Nothing ) ->
            span [ class authorClass ] (contents shown)

        _ ->
            text ""


fedDateLabel : Shared.Model -> FedMedia.Item -> String
fedDateLabel shared item =
    item.post.createdAt
        |> Maybe.map (\ts -> SharedTime.formatDate shared.time.browserTimeZone.zone (timestampToPosix ts))
        |> Maybe.withDefault ""


{-| A video from a Mastodon/Bluesky post -- `videoCard`'s counterpart, opening in the same viewer.
-}
fedVideoCard : Shared.Model -> Bool -> FedMedia.Item -> Html Msg
fedVideoCard shared showHost item =
    div [ class "media-card video-card" ]
        [ button [ class "media-card-thumb", onClick (FedMediaClicked item.host item.media.id), attribute "aria-label" ("Play " ++ fedTitle item) ]
            (MediaRenderer.posterFrame "🎬" (MediaRenderer.videoPosterUrl Nothing Nothing item.media))
        , div [ class "media-card-meta" ]
            [ button [ class "media-card-title", onClick (FedMediaClicked item.host item.media.id) ] [ text (fedTitle item) ]
            , div [ class "media-card-sub" ]
                [ fedAuthorLink shared True item
                , span [ class "media-card-date" ] [ text (fedDateLabel shared item) ]
                ]
            , hostBadge showHost item.host
            ]
        ]


{-| A track from a Mastodon post -- `audioRow`'s counterpart, playing in the same bottom player.
-}
fedAudioRow : Shared.Model -> Int -> Bool -> FedMedia.Item -> Html Msg
fedAudioRow shared queueGeneration showHost item =
    let
        nowPlaying : Maybe Bool
        nowPlaying =
            let
                player : AudioPlayerPanel.Model
                player =
                    shared.panels.audioPlayerPanel
            in
            if player.currentId == Just item.media.id && player.targetHost == item.host then
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
        [ button [ class "media-card-thumb", onClick (FedMediaClicked item.host item.media.id), attribute "aria-label" ("Play " ++ fedTitle item) ]
            [ span [ class "media-card-thumb-placeholder" ] [ text "🎵" ]
            , case nowPlaying of
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
                    span [ class "media-card-play" ] [ text Glyph.play ]
            ]
        , div [ class "media-card-meta" ]
            [ button [ class "media-card-title", onClick (FedMediaClicked item.host item.media.id) ] [ text (fedTitle item) ]
            , div [ class "media-card-sub" ]
                [ fedAuthorLink shared True item
                , hostBadge showHost item.host
                , span [ class "media-card-date" ] [ text (fedDateLabel shared item) ]
                ]
            ]
        , Html.Keyed.node "span"
            [ class "audio-row-queue" ]
            [ ( String.fromInt queueGeneration
              , span [ class "audio-row-queue-inner", attribute "title" "Add to queue" ]
                    [ AudioPlayerPanel.queueIcon
                    , Html.select
                        [ class "audio-row-queue-select"
                        , attribute "aria-label" ("Add " ++ fedTitle item ++ " to queue")
                        , onInput (FedQueuePicked item.host item.media.id)
                        ]
                        [ Html.option [ value "", Html.Attributes.disabled True, Html.Attributes.selected True ] [ text "Queue" ]
                        , Html.option [ value "next" ] [ text "Add Next In Queue" ]
                        , Html.option [ value "last" ] [ text "Add To Queue" ]
                        ]
                    ]
              )
            ]
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
