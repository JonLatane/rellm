module Components.FederatedThread exposing (Actions, Config, ancestorsView, postActionsView, repliesView)

{-| Renders a Mastodon/Bluesky post's surrounding conversation (see `Shared.Federation.Common.Thread`)
with the same `Components.Posts.replyCard` Rellm's own replies use. Ancestors and replies alike are
starrable, and a thread arrives fully fetched (no load-more); replies additionally get the Reply/Edit/Delete
buttons the calling page's `Config` supplies (ancestors stay read-only). `ancestorsView`
goes above the post itself, `repliesView` below it; the latter is a static `Components.PostReplies`
(see `PostReplies.initStatic`), so it gets the same FLIP-animated expand/collapse as a Rellm thread.
-}

import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.PostReplies as PostReplies
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Post)
import Shared.AccountsPanel as AccountsPanel
import Shared.Federation.Actions as FederationActions
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import Shared.Federation.Common exposing (Thread)


type alias Config msg =
    { time : SharedTime.Model
    , basePath : String
    , viewingServerHost : String

    -- The `"mastodon:" ++ instanceHost` / `"bluesky:"` tag every post in the thread is rendered
    -- under -- see `Components.Posts.isFederatedHost`.
    , postServerHost : String
    , mediaPlayState : MediaRenderer.Model
    , onMediaPlayClicked : String -> msg
    , onMediaClicked : Post -> String -> msg
    , accounts : AccountsPanel.Model
    , starredPanel : StarredPanel.Model
    , onStarredPanelMsg : StarredPanel.Msg -> msg

    , actions : Actions msg
    }


{-| What the Reply/Edit/Delete buttons send for a given post. Which buttons show is decided here, from
the connected Mastodon/Bluesky accounts (`Shared.Federation.Actions`): Reply needs any usable account for
the service, Edit/Delete the account that wrote the post.
-}
type alias Actions msg =
    { onReply : Post -> msg
    , onEdit : Post -> msg
    , onDelete : Post -> msg
    }


canReply : AccountsPanel.Model -> String -> Post -> Bool
canReply accounts host post =
    not (Posts.isDeleted post) && FederationActions.serverAccountFor accounts host /= Nothing


isOwn : AccountsPanel.Model -> String -> Post -> Bool
isOwn accounts host post =
    FederationActions.ownAccountFor accounts host post /= Nothing


{-| The Reply/Edit/Delete row under the post being viewed (nothing if no account can do any of them).
-}
postActionsView : Config msg -> Post -> Html msg
postActionsView config post =
    let
        buttons : List (Html msg)
        buttons =
            List.filterMap identity
                [ if canReply config.accounts config.postServerHost post then
                    Just (button [ class "post-reply-button", onClick (config.actions.onReply post) ] [ text "Reply" ])

                  else
                    Nothing
                , if isOwn config.accounts config.postServerHost post then
                    Just (button [ class "post-reply-button", onClick (config.actions.onEdit post) ] [ text "Edit" ])

                  else
                    Nothing
                , if isOwn config.accounts config.postServerHost post then
                    Just (button [ class "post-delete-button", onClick (config.actions.onDelete post) ] [ text "Delete" ])

                  else
                    Nothing
                ]
    in
    if List.isEmpty buttons then
        text ""

    else
        div [ class "post-actions" ] buttons


{-| The posts this one replies to, oldest first -- nothing at all if it isn't a reply.
-}
ancestorsView : Config msg -> Thread -> Html msg
ancestorsView config thread =
    if List.isEmpty thread.ancestors then
        text ""

    else
        div [ class "federated-thread-ancestors" ]
            (List.map (card config 0) thread.ancestors)


{-| Every reply, flattened depth-first with increasing indentation and per-reply expand/collapse --
just `Components.PostReplies.view` over a model made by `PostReplies.initStatic`. `toMsg` wraps its
`Msg` into the calling page's own.
-}
repliesView : Config msg -> (PostReplies.Msg -> msg) -> PostReplies.Model -> Html msg
repliesView config toMsg model =
    PostReplies.view
        { time = config.time
        , basePath = config.basePath
        , viewingServerHost = config.viewingServerHost
        , postServerHost = config.postServerHost
        , maybeServer = Nothing
        , maybeAccount = Nothing
        , onMediaClicked = config.onMediaClicked
        , mediaPlayState = config.mediaPlayState
        , onMediaPlayClicked = config.onMediaPlayClicked
        , onReplyClicked =
            \post ->
                if canReply config.accounts config.postServerHost post then
                    Just (config.actions.onReply post)

                else
                    Nothing
        , onEditClicked =
            \post ->
                if isOwn config.accounts config.postServerHost post then
                    Just (config.actions.onEdit post)

                else
                    Nothing
        , onDeleteClicked =
            \post ->
                if isOwn config.accounts config.postServerHost post then
                    Just (config.actions.onDelete post)

                else
                    Nothing
        , toMsg = toMsg
        , accounts = config.accounts
        , starredPanel = config.starredPanel
        , onStarredPanelMsg = config.onStarredPanelMsg
        }
        model


card : Config msg -> Int -> Post -> Html msg
card config depth post =
    let
        -- Reflects this session's own star/unstar clicks immediately -- see `StarredPanel.freshestPost`.
        displayPost : Post
        displayPost =
            StarredPanel.freshestPost config.postServerHost post config.starredPanel
    in
    Posts.replyCard
        config.time
        config.basePath
        config.viewingServerHost
        config.postServerHost
        Nothing
        Nothing
        (config.onMediaClicked post)
        config.mediaPlayState
        config.onMediaPlayClicked
        depth
        True
        False
        False
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        (StarredPanel.isStarred config.postServerHost displayPost config.starredPanel)
        (StarredPanel.toggleStarMsg config.accounts config.postServerHost displayPost
            |> Maybe.map config.onStarredPanelMsg
        )
        displayPost
