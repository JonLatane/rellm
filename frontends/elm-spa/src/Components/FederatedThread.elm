module Components.FederatedThread exposing (Config, ancestorsView, repliesView)

{-| Renders a Mastodon/Bluesky post's surrounding conversation (see `Shared.Federation.Common.Thread`)
with the same `Components.Posts.replyCard` Rellm's own replies use -- read-only (no Reply/load-more
affordances, since a federated thread arrives fully fetched and Rellm can't post into it). `ancestorsView`
goes above the post itself, `repliesView` below it; the latter is a static `Components.PostReplies`
(see `PostReplies.initStatic`), so it gets the same FLIP-animated expand/collapse as a Rellm thread.
-}

import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.PostReplies as PostReplies
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Proto.Rellm exposing (Post)
import Shared.Federation.Common exposing (Thread)


type alias Config msg =
    { basePath : String
    , viewingServerHost : String

    -- The `"mastodon:" ++ instanceHost` / `"bluesky:"` tag every post in the thread is rendered
    -- under -- see `Components.Posts.isFederatedHost`.
    , postServerHost : String
    , mediaPlayState : MediaRenderer.Model
    , onMediaPlayClicked : String -> msg
    , onMediaClicked : Post -> String -> msg
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
        { basePath = config.basePath
        , viewingServerHost = config.viewingServerHost
        , postServerHost = config.postServerHost
        , maybeServer = Nothing
        , maybeAccount = Nothing
        , onMediaClicked = config.onMediaClicked
        , mediaPlayState = config.mediaPlayState
        , onMediaPlayClicked = config.onMediaPlayClicked
        , onReplyClicked = Nothing
        , toMsg = toMsg
        }
        model


card : Config msg -> Int -> Post -> Html msg
card config depth post =
    Posts.replyCard
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
        post
