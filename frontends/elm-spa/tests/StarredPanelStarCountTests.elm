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
        , test "a delta of zero leaves the count alone (a bookmark with no account, or a floor already hit)" <|
            \_ -> Expect.equal 3 (Posts.postStarCount (StarredPanel.withStarCountDelta 0 (withCount 3)))
        , test "taking back what an unstar applied at zero (nothing) leaves zero, rather than inventing a star" <|
            \_ ->
                let
                    before : Post
                    before =
                        withCount 0

                    -- What `ToggleFederatedStar` records as applied: the difference the change really made.
                    applied : Int
                    applied =
                        Posts.postStarCount (StarredPanel.withStarCountChange False before) - Posts.postStarCount before
                in
                before
                    |> StarredPanel.withStarCountChange False
                    |> StarredPanel.withStarCountDelta (negate applied)
                    |> Posts.postStarCount
                    |> Expect.equal 0
        ]
