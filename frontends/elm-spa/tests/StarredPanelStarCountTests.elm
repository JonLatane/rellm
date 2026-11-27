module StarredPanelStarCountTests exposing (suite)

{-| `StarredPanel.withStarCountChange`: the optimistic change to a Mastodon/Bluesky post's own "★ N" when the viewer
stars or unstars it (neither network hands the new count back from a like).
-}

import Components.Posts as Posts
import Expect
import Proto.Rellm exposing (Post, defaultPost)
import Shared.Conversions exposing (int64FromInt)
import Shared.StarredPanel as StarredPanel
import Test exposing (Test, describe, test)


withCount : Int -> Post
withCount n =
    { defaultPost | unauthenticatedStarCount = int64FromInt n }


suite : Test
suite =
    describe "StarredPanel.withStarCountChange"
        [ test "starring adds one" <|
            \_ -> Expect.equal 4 (Posts.postStarCount (StarredPanel.withStarCountChange True (withCount 3)))
        , test "unstarring takes one off" <|
            \_ -> Expect.equal 2 (Posts.postStarCount (StarredPanel.withStarCountChange False (withCount 3)))
        , test "a star then an unstar lands back where it started" <|
            \_ ->
                withCount 7
                    |> StarredPanel.withStarCountChange True
                    |> StarredPanel.withStarCountChange False
                    |> Posts.postStarCount
                    |> Expect.equal 7
        , test "never goes below zero" <|
            \_ -> Expect.equal 0 (Posts.postStarCount (StarredPanel.withStarCountChange False (withCount 0)))
        ]
