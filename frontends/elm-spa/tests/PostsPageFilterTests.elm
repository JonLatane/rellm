module PostsPageFilterTests exposing (suite)

{-| `Components.Pages.PostsPage.filterFeedPosts` -- what a freshly fetched feed has dropped from it: posts a
server's custom nav already features, and (unless DebugTab's "Show Mastodon/Bluesky posts with sensitive
media" is on, i.e. `hideSensitiveMedia` is `False`) federated posts whose media was stripped as sensitive.
When such a post is kept, it's the card's own click-through "sensitive media" notice that guards its media.
-}

import Components.Pages.PostsPage as PostsPage
import Expect
import Proto.Rellm exposing (Post, defaultMediaReference, defaultPost)
import Set
import Shared.Federation.Common exposing (sensitiveMediaHiddenId)
import Test exposing (Test, describe, test)


plain : Post
plain =
    { defaultPost | id = "plain" }


withPicture : Post
withPicture =
    { defaultPost | id = "with-picture", media = [ { defaultMediaReference | id = "real-media-id" } ] }


{-| A Mastodon/Bluesky post whose media was stripped as sensitive: `toPost` leaves just this placeholder.
-}
sensitive : Post
sensitive =
    { defaultPost | id = "sensitive", media = [ { defaultMediaReference | id = sensitiveMediaHiddenId } ] }


featured : Post
featured =
    { defaultPost | id = "featured" }


ids : List Post -> List String
ids =
    List.map .id


suite : Test
suite =
    describe "PostsPage.filterFeedPosts"
        [ test "with hideSensitiveMedia off (the Debug \"show\" switch on), nothing is dropped -- a sensitive post stays, to show its notice" <|
            \_ ->
                PostsPage.filterFeedPosts { hiddenPostIds = Set.empty, hideSensitiveMedia = False } [ plain, sensitive, withPicture ]
                    |> ids
                    |> Expect.equal [ "plain", "sensitive", "with-picture" ]
        , test "with hideSensitiveMedia on (the default), drops posts whose media was hidden as sensitive, keeping everything else" <|
            \_ ->
                PostsPage.filterFeedPosts { hiddenPostIds = Set.empty, hideSensitiveMedia = True } [ plain, sensitive, withPicture ]
                    |> ids
                    |> Expect.equal [ "plain", "with-picture" ]
        , test "hiddenPostIds drops those posts (the custom-nav filter), whatever hideSensitiveMedia says" <|
            \_ ->
                PostsPage.filterFeedPosts { hiddenPostIds = Set.singleton "featured", hideSensitiveMedia = False } [ plain, featured, sensitive ]
                    |> ids
                    |> Expect.equal [ "plain", "sensitive" ]
        , test "the two filters combine" <|
            \_ ->
                PostsPage.filterFeedPosts { hiddenPostIds = Set.singleton "featured", hideSensitiveMedia = True } [ plain, featured, sensitive, withPicture ]
                    |> ids
                    |> Expect.equal [ "plain", "with-picture" ]
        , test "keeps the feed's order" <|
            \_ ->
                PostsPage.filterFeedPosts { hiddenPostIds = Set.empty, hideSensitiveMedia = True } [ withPicture, sensitive, plain ]
                    |> ids
                    |> Expect.equal [ "with-picture", "plain" ]
        ]
