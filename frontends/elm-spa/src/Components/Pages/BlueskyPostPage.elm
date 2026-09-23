module Components.Pages.BlueskyPostPage exposing (Model, Msg, init, title, update, view)

{-| A single Bluesky post, read-only -- no reply/edit/delete/visibility/moderation/sync-destination
affordances (none of that makes sense for a post Rellm doesn't own), and no replies tree (Rellm has
no way to fetch a Bluesky post's own replies -- a "for now" gap). Just its author, content, and a
link back to the original.

Split out of `Components.Pages.PostPage` (which now only ever handles real Rellm posts) into its own
dedicated page so `Pages.Post.PostId_` can route to this directly once
`Components.Posts.parseFederatedPostId` recognizes the id as Bluesky's -- see that module's own doc,
and `Components.Pages.MastodonPostPage` for the ActivityPub counterpart.

-}

import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.Posts as Posts
import Effect exposing (Effect)
import Html exposing (Html, a, button, div, p, text)
import Html.Attributes exposing (class, href, rel, target)
import Html.Events exposing (onClick)
import Http
import Proto.Rellm exposing (Post)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import Shared.Federation.Bluesky as Bluesky
import Shared.MediaViewerPanel as MediaViewerPanel
import Task


type alias Model =
    { uri : String
    , postStatus : PostStatus

    -- Starts `False` on every fresh `init` (a new post visited never
    -- inherits a previous one's reveal) -- set `True` by `RevealSensitiveMediaClicked`.
    -- Meaningless (never consulted) unless `postStatus` is `PostLoaded _ True`, i.e. AT Proto
    -- actually labeled this post -- see `federatedPostView`'s own doc.
    , sensitiveMediaRevealed : Bool
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
    = GotPost String (Result Http.Error ( Maybe BlueskyAccount, Post, Bool ))
    | MediaPlayClicked String
    | MediaImageClicked String
    | RevealSensitiveMediaClicked


{-| `uri` comes straight from `Components.Posts.parseFederatedPostId`'s `BlueskyPostId` -- see that
type's own doc. Fetched using whichever connected Bluesky account comes first -- reading a public
post doesn't need to be _that_ account's own, any connected token works (see
`Shared.Federation.Bluesky.fetchPost`'s own doc) -- and fails outright (a bare `Http.BadStatus 401`,
landing on `PostFailed`, same as a real auth failure would) if none is connected at all, since AT
Protocol has no anonymous access to anything. Goes through `BlueskyAccounts.performWithBlueskyAccount`
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

        fetchTask : Task.Task Http.Error ( Maybe BlueskyAccount, Post, Bool )
        fetchTask =
            case shared.accounts.blueskyAccounts of
                account :: _ ->
                    BlueskyAccounts.performWithBlueskyAccount account (\accessToken -> Bluesky.fetchPost accessToken uri)
                        |> Task.map
                            (\( refreshedAccount, ( post, sensitive ) ) ->
                                ( if refreshedAccount.accessToken == account.accessToken then
                                    Nothing

                                  else
                                    Just refreshedAccount
                                , post
                                , sensitive
                                )
                            )

                [] ->
                    Task.fail (Http.BadStatus 401)
    in
    ( { uri = uri, postStatus = LoadingPost, sensitiveMediaRevealed = False }
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
update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotPost _ (Ok ( maybeRefreshedAccount, post, sensitive )) ->
            ( { model | postStatus = PostLoaded post sensitive }
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

        RevealSensitiveMediaClicked ->
            ( { model | sensitiveMediaRevealed = True }, Effect.none )


view : Shared.Model -> Model -> Html Msg
view shared model =
    case model.postStatus of
        LoadingPost ->
            p [ class "post-loading" ] [ text "Loading…" ]

        PostFailed ->
            p [ class "post-error" ] [ text "Couldn't load this post. Maybe it was deleted, or maybe it's private." ]

        PostLoaded post sensitive ->
            federatedPostView shared model.sensitiveMediaRevealed sensitive post


{-| No title, no URL row -- just the author (linking to their own `Components.Pages.BlueskyUserProfilePage`,
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
    div [ class "post-detail" ]
        [ div [ class "federated-service-label" ] [ text "⇄ Bluesky" ]
        , Authors.link "" "" "bluesky:" Nothing Nothing post.author
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
