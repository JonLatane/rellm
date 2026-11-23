module StarredPanelLikeRecordsTests exposing (suite)

{-| `Shared.StarredPanel`'s remembered Bluesky like records: the `at://` URI a like got when this session made
it, which lets starring then quickly unstarring still delete it while Bluesky's own `viewer.like` is empty. A like
record belongs to the account that made it, so what's remembered must never leak from one account to another.
-}

import Expect
import Json.Encode as Encode
import Shared.Federation.Bluesky as Bluesky
import Shared.StarredPanel as StarredPanel
import Test exposing (Test, describe, test)


post : String
post =
    "at://did:plc:author/app.bsky.feed.post/3abc"


fresh : StarredPanel.Model
fresh =
    StarredPanel.init (Encode.list Encode.string [])


suite : Test
suite =
    describe "StarredPanel remembered like records"
        [ test "nothing is remembered to begin with" <|
            \_ ->
                StarredPanel.knownLike "alice.test" post fresh
                    |> Expect.equal Nothing
        , test "a created like is remembered for the account that made it" <|
            \_ ->
                fresh
                    |> StarredPanel.noteLikeChange "alice.test" post (Bluesky.Created "at://did:plc:alice/app.bsky.feed.like/1")
                    |> StarredPanel.knownLike "alice.test" post
                    |> Expect.equal (Just "at://did:plc:alice/app.bsky.feed.like/1")
        , test "...and is never handed to another account (their like is not that record)" <|
            \_ ->
                fresh
                    |> StarredPanel.noteLikeChange "alice.test" post (Bluesky.Created "at://did:plc:alice/app.bsky.feed.like/1")
                    |> StarredPanel.knownLike "bob.test" post
                    |> Expect.equal Nothing
        , test "two accounts liking the same post each keep their own record" <|
            \_ ->
                let
                    model : StarredPanel.Model
                    model =
                        fresh
                            |> StarredPanel.noteLikeChange "alice.test" post (Bluesky.Created "at://did:plc:alice/app.bsky.feed.like/1")
                            |> StarredPanel.noteLikeChange "bob.test" post (Bluesky.Created "at://did:plc:bob/app.bsky.feed.like/2")
                in
                ( StarredPanel.knownLike "alice.test" post model, StarredPanel.knownLike "bob.test" post model )
                    |> Expect.equal ( Just "at://did:plc:alice/app.bsky.feed.like/1", Just "at://did:plc:bob/app.bsky.feed.like/2" )
        , test "deleting a like forgets it, only for that account" <|
            \_ ->
                let
                    model : StarredPanel.Model
                    model =
                        fresh
                            |> StarredPanel.noteLikeChange "alice.test" post (Bluesky.Created "at://did:plc:alice/app.bsky.feed.like/1")
                            |> StarredPanel.noteLikeChange "bob.test" post (Bluesky.Created "at://did:plc:bob/app.bsky.feed.like/2")
                            |> StarredPanel.noteLikeChange "alice.test" post Bluesky.Deleted
                in
                ( StarredPanel.knownLike "alice.test" post model, StarredPanel.knownLike "bob.test" post model )
                    |> Expect.equal ( Nothing, Just "at://did:plc:bob/app.bsky.feed.like/2" )
        , test "a change that did nothing leaves what is remembered alone" <|
            \_ ->
                fresh
                    |> StarredPanel.noteLikeChange "alice.test" post (Bluesky.Created "at://did:plc:alice/app.bsky.feed.like/1")
                    |> StarredPanel.noteLikeChange "alice.test" post Bluesky.NothingToDo
                    |> StarredPanel.knownLike "alice.test" post
                    |> Expect.equal (Just "at://did:plc:alice/app.bsky.feed.like/1")
        ]
