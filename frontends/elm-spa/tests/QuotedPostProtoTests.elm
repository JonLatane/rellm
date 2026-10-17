module QuotedPostProtoTests exposing (suite)

{-| `Post.quotedPostId`/`quotedPost` (protos/posts.proto, fields 28/27) survive the same binary
encode/decode the gRPC-Web client does for every Post -- including a `quotedPost` itself carrying
its own `quotedPostId`, which is what the server returns (one level hydrated).
-}

import Expect
import Proto.Rellm exposing (Post, decodePost, defaultPost, encodePost, wrapPost)
import Protobuf.Decode as Decode
import Protobuf.Encode as Encode
import Test exposing (Test, describe, test)


roundTrip : Post -> Maybe Post
roundTrip post =
    Decode.decode decodePost (Encode.encode (encodePost post))


suite : Test
suite =
    describe "Post.quotedPostId / quotedPost"
        [ test "a quotedPostId round-trips" <|
            \_ ->
                { defaultPost | id = "2", quotedPostId = Just "1" }
                    |> roundTrip
                    |> Maybe.map .quotedPostId
                    |> Expect.equal (Just (Just "1"))
        , test "a nested quotedPost round-trips along with its own quotedPostId" <|
            \_ ->
                { defaultPost
                    | id = "3"
                    , quotedPostId = Just "2"
                    , quotedPost = Just (wrapPost { defaultPost | id = "2", content = Just "quoted", quotedPostId = Just "1" })
                }
                    |> roundTrip
                    |> Maybe.andThen .quotedPost
                    |> Maybe.map (\quoted -> ( quoted |> Proto.Rellm.unwrapPost |> .content, quoted |> Proto.Rellm.unwrapPost |> .quotedPostId ))
                    |> Expect.equal (Just ( Just "quoted", Just "1" ))
        , test "no quote at all stays Nothing" <|
            \_ ->
                { defaultPost | id = "1" }
                    |> roundTrip
                    |> Maybe.map (\post -> ( post.quotedPostId, post.quotedPost == Nothing ))
                    |> Expect.equal (Just ( Nothing, True ))
        ]
