module Components.FederatedThread exposing (Config, ancestorsView, repliesView)

{-| Renders a Mastodon/Bluesky post's surrounding conversation (see `Shared.Federation.Common.Thread`)
with the same `Components.Posts.replyCard` Rellm's own replies use -- read-only (no Reply/load-more
affordances; ancestors and replies alike are starrable, since a federated thread arrives fully fetched and Rellm can't post into it). `ancestorsView`
goes above the post itself, `repliesView` below it; the latter is a static `Components.PostReplies`
(see `PostReplies.initStatic`), so it gets the same FLIP-animated expand/collapse as a Rellm thread.
-}

import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.PostReplies as PostReplies
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Proto.Rellm exposing (Post)
import Shared.AccountsPanel as AccountsPanel
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
    }


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
        , onReplyClicked = Nothing
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
        (StarredPanel.isStarred config.postServerHost displayPost config.starredPanel)
        (StarredPanel.toggleStarMsg config.accounts config.postServerHost displayPost
            |> Maybe.map config.onStarredPanelMsg
        )
        displayPost
