module Federation.BlueskyTests exposing (suite)

import Expect
import Json.Decode as Decode
import Proto.Rellm exposing (unwrapMediaReference)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Federation.Bluesky as Bluesky
import Support.BlueskyFactory as Factory exposing (defaultOverrides)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.Federation.Bluesky"
        [ describe "decoder"
            [ test "decodes a real-shaped feedViewPost into the same value `toPost` would get directly" <|
                \_ ->
                    Factory.feedViewPostJson defaultOverrides
                        |> Decode.decodeString Bluesky.decoder
                        |> Expect.equal (Ok (Factory.feedPost defaultOverrides))
            , test "no top-level reply key means isReply is False" <|
                \_ ->
                    Factory.feedViewPostJson { defaultOverrides | isReply = False }
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .isReply
                        |> Expect.equal (Ok False)
            , test "a top-level reply key (whatever it contains) means isReply is True" <|
                \_ ->
                    Factory.feedViewPostJson { defaultOverrides | isReply = True }
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .isReply
                        |> Expect.equal (Ok True)
            , test "a missing displayName decodes to no real name" <|
                \_ ->
                    Factory.feedViewPostJson { defaultOverrides | displayName = Nothing }
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .authorDisplayName
                        |> Expect.equal (Ok Nothing)
            ]
        , describe "toPost"
            [ test "id is the bare at:// URI, unnamespaced -- the synthetic host alongside it (never id alone) is what disambiguates it from a real Rellm post id" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .id
                        |> Expect.equal "at://did:plc:abc123/app.bsky.feed.post/xyz789"
            , test "is always GLOBALPUBLIC -- AT Protocol has no private-post concept" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .visibility
                        |> Expect.equal GLOBALPUBLIC
            , test "a non-reply feed post becomes a POST" <|
                \_ ->
                    Factory.feedPost { defaultOverrides | isReply = False }
                        |> Bluesky.toPost
                        |> .context
                        |> Expect.equal POST
            , test "a reply feed post becomes a REPLY" <|
                \_ ->
                    Factory.feedPost { defaultOverrides | isReply = True }
                        |> Bluesky.toPost
                        |> .context
                        |> Expect.equal REPLY
            , test "builds a real bsky.app web URL out of the at:// URI's own rkey" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .link
                        |> Expect.equal (Just "https://bsky.app/profile/alice.bsky.social/post/xyz789")
            , test "carries the author's own avatar as a MediaReference.url, not a Rellm media id" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .author
                        |> Maybe.andThen .avatar
                        |> Maybe.map unwrapMediaReference
                        |> Maybe.andThen .url
                        |> Expect.equal (Just "https://cdn.bsky.app/img/avatar/alice.jpg")
            , test "the author's own handle is used as their Rellm username, unqualified (already globally unique)" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .author
                        |> Maybe.andThen .username
                        |> Expect.equal (Just "alice.bsky.social")
            ]
        ]
