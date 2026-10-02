module Components.Bluesky.BlueskyPostPage exposing (Model, Msg, init, subscriptions, title, update, view)

{-| A single Bluesky post, read-only -- no reply/edit/delete/visibility/moderation/sync-destination
affordances (none of that makes sense for a post Rellm doesn't own). Just its author, content, a link
back to the original, and its conversation (the posts it replies to above it, its own reply tree
below -- see `Shared.Federation.Bluesky.fetchThread` and `Components.FederatedThread`).

Split out of `Components.Pages.PostPage` (which now only ever handles real Rellm posts) into its own
dedicated page so `Pages.Post.PostId_` can route to this directly once
`Components.Posts.parseFederatedPostId` recognizes the id as Bluesky's -- see that module's own doc,
and `Components.Mastodon.MastodonPostPage` for the ActivityPub counterpart.

-}

import Components.Authors as Authors
import Components.FederatedThread as FederatedThread
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.PostReplies as PostReplies
import Components.Posts as Posts
import Effect exposing (Effect)
import Html exposing (Html, a, button, div, p, span, text)
import Html.Attributes exposing (class, href, rel, target)
import Html.Events exposing (onClick)
import Http
import Proto.Rellm exposing (Post)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Common as Common exposing (Thread)
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.StarredPanel as StarredPanel
import Task


type alias Model =
    { uri : String
    , postStatus : PostStatus

    -- Starts `False` on every fresh `init` (a new post visited never
    -- inherits a previous one's reveal) -- set `True` by `RevealSensitiveMediaClicked`.
    -- Meaningless (never consulted) unless `postStatus` is `PostLoaded _ True`, i.e. AT Proto
    -- actually labeled this post -- see `federatedPostView`'s own doc.
    , sensitiveMediaRevealed : Bool

    -- Fetched right after the post itself, best-effort -- stays `emptyThread` if that fails.
    , thread : Thread

    -- `thread.replies` as a static, collapsible `Components.PostReplies` tree.
    , replies : PostReplies.Model
    }


{-| `PostLoaded post sensitive` -- `sensitive` is `FeedPost.sensitive` itself (see
`Bluesky.fetchPost`'s own doc on why it travels alongside `Post` rather than folded into it):
`post.media` itself already carries this post's real media either way (`fetchPost` always uses
`Bluesky.toPostIncludingSensitiveMedia`, unlike every feed/card context), so this is
`federatedPostView`'s only way to tell "flagged, gate it behind a click" apart from "never flagged,
show it straight away".
-}
type PostStatus
    = LoadingPost
    | PostLoaded Post Bool
    | PostFailed


type Msg
    = GotPost String (Result Http.Error ( Maybe BlueskyAccount, ( Post, Bool ), Thread ))
    | MediaPlayClicked String
    | MediaImageClicked String
    | ThreadMediaClicked Post String
    | RevealSensitiveMediaClicked
    | StarredPanelMsg StarredPanel.Msg
    | RepliesMsg PostReplies.Msg


{-| `uri` comes straight from `Components.Posts.parseFederatedPostId`'s `BlueskyPostId` -- see that
type's own doc. Fetched using whichever connected Bluesky account comes first -- reading a public
post doesn't need to be _that_ account's own, any connected token works (see
`Shared.Federation.Bluesky.fetchPost`'s own doc) -- and falls back to anonymous reads from Bluesky's public AppView if none is connected. Goes through `BlueskyAccounts.performWithBlueskyAccount`
same as `Components.Pages.PostsPage.fetchFeedSource`'s own `BlueskyFeed` case, so a since-expired
access token gets one refresh-and-retry rather than failing outright -- see `update`'s own handling
of the rotated/reauth-needed account this can come back with.
-}
init : Shared.Model -> String -> ( Model, Effect Msg )
init shared uri =
    let
        actingHandle : String
        actingHandle =
            List.head shared.accounts.blueskyAccounts |> Maybe.map .handle |> Maybe.withDefault ""

        fetchTask : Task.Task Http.Error ( Maybe BlueskyAccount, ( Post, Bool ), Thread )
        fetchTask =
            case shared.accounts.blueskyAccounts of
                account :: _ ->
                    -- The thread is fetched with the (possibly just-refreshed) token the post fetch
                    -- ended up with, strictly after it rather than alongside -- AT Proto refresh
                    -- tokens are single-use (see `BlueskyAccount`'s own doc), so two concurrent
                    -- `performWithBlueskyAccount` calls could race to rotate the same one.
                    BlueskyAccounts.performWithBlueskyAccount account (\accessToken -> Bluesky.fetchPost accessToken uri)
                        |> Task.andThen
                            (\( refreshedAccount, ( post, sensitive ) ) ->
                                Bluesky.fetchThread refreshedAccount.accessToken uri
                                    |> Task.onError (\_ -> Task.succeed Common.emptyThread)
                                    |> Task.map
                                        (\thread ->
                                            ( if refreshedAccount.accessToken == account.accessToken then
                                                Nothing

                                              else
                                                Just refreshedAccount
                                            , ( post, sensitive )
                                            , thread
                                            )
                                        )
                            )

                -- No connected account -- read anonymously from the public AppView (an empty
                -- token, see `Bluesky.fetchPost`), nothing to refresh/persist.
                [] ->
                    Bluesky.fetchPost "" uri
                        |> Task.andThen
                            (\( post, sensitive ) ->
                                Bluesky.fetchThread "" uri
                                    |> Task.onError (\_ -> Task.succeed Common.emptyThread)
                                    |> Task.map (\thread -> ( Nothing, ( post, sensitive ), thread ))
                            )
    in
    ( { uri = uri, postStatus = LoadingPost, sensitiveMediaRevealed = False, thread = Common.emptyThread, replies = PostReplies.initStatic "bluesky:" [] }
    , fetchTask |> Task.attempt (GotPost actingHandle) |> Effect.fromCmd
    )


{-| A successful fetch persists a rotated access/refresh token pair, if `performWithBlueskyAccount`
had to refresh one to get here (see that function's own doc on why the tokens it carries may have
silently rotated), via `Shared.AccountsPanel.BlueskyAccountRefreshed`; a final failure worth flagging
as `needsReauth` (see `BlueskyAccounts.isReauthError`) marks it the same way
`Components.Pages.PostsPage`'s own `fromBlueskyResult` does, so a revoked/expired account shows its
"Reconnect" affordance in the Accounts Panel rather than just failing silently every time this page
(or any other Bluesky-post link) is opened.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map RepliesMsg (PostReplies.subscriptions model.replies)


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotPost _ (Ok ( maybeRefreshedAccount, ( post, sensitive ), thread )) ->
            ( { model | postStatus = PostLoaded post sensitive, thread = thread, replies = PostReplies.initStatic "bluesky:" thread.replies }
            , maybeRefreshedAccount
                |> Maybe.map (AccountsPanel.BlueskyAccountRefreshed >> Shared.AccountsPanelMsg >> Effect.fromShared)
                |> Maybe.withDefault Effect.none
            )

        GotPost handle (Err err) ->
            ( { model | postStatus = PostFailed }
            , if BlueskyAccounts.isReauthError err && handle /= "" then
                Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.MarkBlueskyAccountNeedsReauth handle))

              else
                Effect.none
            )

        MediaPlayClicked mediaId ->
            ( model, Effect.fromShared (Shared.MediaRendererMsg (MediaRenderer.PlayClicked mediaId)) )

        MediaImageClicked mediaId ->
            case model.postStatus of
                PostLoaded post _ ->
                    ( model
                    , Effect.fromShared
                        (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open post.media (Just post) mediaId "bluesky:"))
                    )

                _ ->
                    ( model, Effect.none )

        ThreadMediaClicked post mediaId ->
            ( model
            , Effect.fromShared (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open post.media (Just post) mediaId "bluesky:"))
            )

        RevealSensitiveMediaClicked ->
            ( { model | sensitiveMediaRevealed = True }, Effect.none )

        RepliesMsg subMsg ->
            PostReplies.updateStatic subMsg model.replies
                |> Tuple.mapFirst (\replies -> { model | replies = replies })
                |> Tuple.mapSecond (Effect.map RepliesMsg)

        StarredPanelMsg subMsg ->
            ( model, Effect.fromShared (Shared.StarredPanelMsg subMsg) )


{-| `host` for `StarredPanel`'s keying/lookups -- the same `"bluesky:"` tag
`federatedPostView`'s own `Authors.link` call and every Bluesky post card
use (see `Components.Posts.isFederatedHost`).
-}
starHost : String
starHost =
    "bluesky:"


view : Shared.Model -> Model -> Html Msg
view shared model =
    case model.postStatus of
        LoadingPost ->
            p [ class "post-loading" ] [ text "Loading…" ]

        PostFailed ->
            p [ class "post-error" ] [ text "Couldn't load this post. Maybe it was deleted, or maybe it's private." ]

        PostLoaded post sensitive ->
            let
                -- Reflects this session's own star/unstar clicks immediately
                -- -- see `StarredPanel.freshestPost`'s own doc.
                displayPost : Post
                displayPost =
                    StarredPanel.freshestPost starHost post shared.panels.starredPanel
            in
            div []
                [ FederatedThread.ancestorsView (threadConfig shared) model.thread
                , federatedPostView shared model.sensitiveMediaRevealed sensitive displayPost
                , FederatedThread.repliesView (threadConfig shared) RepliesMsg model.replies
                ]


threadConfig : Shared.Model -> FederatedThread.Config Msg
threadConfig shared =
    { basePath = shared.basePath
    , viewingServerHost = shared.accounts.mainFrontendHost
    , postServerHost = starHost
    , mediaPlayState = shared.mediaRenderer
    , onMediaPlayClicked = MediaPlayClicked
    , onMediaClicked = ThreadMediaClicked
    }


{-| No title, no URL row -- just the author (linking to their own `Components.Bluesky.BlueskyUserProfilePage`,
via `Authors.link`, same as any other federated post card does), the content, this post's own media
(rendered the same `MultiMediaRenderer.view` way `Components.Posts.postDetail` renders a real Rellm
post's, since `Shared.Federation.Bluesky.toPost` now populates `Post.media` the same way -- see its
own doc), and a "View original" link back to the real post on Bluesky. No real `RellmServer`/
`RellmAccount` are involved (a federated post's media is never Rellm-hosted -- see
`Components.MediaRenderer.authorizedUrl`'s own doc on how `MediaReference.url` bypasses both), so
`noServer` is a placeholder never actually dereferenced.

`sensitive && not sensitiveMediaRevealed` shows a "click to view" gate in place of the real media --
`post.media` already carries it either way (`Bluesky.fetchPost` always uses
`toPostIncludingSensitiveMedia`), unlike `Components.Posts.postCard`'s own hidden-placeholder gate
(this is the one page that's allowed to show it at all, once asked -- see that module's own doc on
why a feed/card context never gets this far). Once revealed (or never flagged to begin with), renders
exactly like any other post's media.

-}
federatedPostView : Shared.Model -> Bool -> Bool -> Post -> Html Msg
federatedPostView shared sensitiveMediaRevealed sensitive post =
    let
        starred : Bool
        starred =
            StarredPanel.isStarred starHost post shared.panels.starredPanel

        onStarClicked : Maybe Msg
        onStarClicked =
            StarredPanel.toggleStarMsg shared.accounts starHost post |> Maybe.map StarredPanelMsg
    in
    div [ class "post-detail" ]
        [ div [ class "federated-service-label" ] [ text "⇄ Bluesky" ]
        , Authors.link "" "" starHost Nothing Nothing post.author
        , div [ class "post-detail-meta" ] [ span [ class "post-meta-right" ] [ Posts.starButton starHost starred onStarClicked post ] ]
        , Markdown.view [ class "post-detail-content" ] (Maybe.withDefault "" post.content)
        , if sensitive && not sensitiveMediaRevealed && not (List.isEmpty post.media) then
            button
                [ class "post-detail-sensitive-media-notice"
                , onClick RevealSensitiveMediaClicked
                ]
                [ text "This post contains sensitive media. Click to view." ]

          else
            MultiMediaRenderer.view post.postMediaLayout noServer Nothing shared.mediaRenderer MediaPlayClicked MediaImageClicked post.media
        , case post.link of
            Just link ->
                a
                    [ class "post-link"
                    , href link
                    , target "_blank"
                    , rel "noopener noreferrer"
                    ]
                    [ text ("View original: " ++ Posts.stripLinkScheme link) ]

            Nothing ->
                text ""
        ]


{-| A placeholder `RellmServer` for `federatedPostView`'s `MultiMediaRenderer.view` call -- never
actually dereferenced, since `post.media` here is always `.url`-only, externally-hosted media (see
`federatedPostView`'s own doc).
-}
noServer : RellmServer
noServer =
    { frontendHost = "", enabled = False, connected = Nothing, sortOrder = 0 }


{-| Just the subtitle -- the loaded post's own title, or "Post" before it's loaded -- for the
calling page's own `UI.pageTitle`. Mirrors `Components.Pages.PostPage.titleFor`.
-}
title : Model -> String
title model =
    case model.postStatus of
        PostLoaded post _ ->
            Posts.postTitleText post

        _ ->
            "Post"
