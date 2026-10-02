module Components.FederatedThread exposing (Config, ancestorsView, repliesView)

{-| Renders a Mastodon/Bluesky post's surrounding conversation (see `Shared.Federation.Common.Thread`)
with the same `Components.Posts.replyCard` Rellm's own replies use -- read-only (no Reply/load-more/
collapse affordances, since a federated thread arrives fully fetched and Rellm can't post into it).
`ancestorsView` goes above the post itself, `repliesView` below it.
-}

import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Html exposing (Html, div, h3, text)
import Html.Attributes exposing (class)
import Proto.Rellm exposing (Post, unwrapPost)
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


{-| Every reply, flattened depth-first with increasing indentation (`replyCard`'s own `depth`), the
same way `Components.PostReplies.view` flattens a Rellm thread.
-}
repliesView : Config msg -> Thread -> Html msg
repliesView config thread =
    if List.isEmpty thread.replies then
        text ""

    else
        div [ class "federated-thread-replies" ]
            (h3 [ class "federated-thread-heading" ] [ text "Replies" ]
                :: flatten config 1 thread.replies
            )


flatten : Config msg -> Int -> List Post -> List (Html msg)
flatten config depth posts =
    List.concatMap
        (\post ->
            card config depth post
                :: flatten config (depth + 1) (List.map unwrapPost post.replies)
        )
        posts


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
