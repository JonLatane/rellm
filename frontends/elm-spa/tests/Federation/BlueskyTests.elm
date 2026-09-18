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
            , test "decodes an app.bsky.embed.images#view embed's images" <|
                \_ ->
                    let
                        overrides =
                            { defaultOverrides
                                | images =
                                    [ { url = "https://cdn.bsky.app/img/feed_fullsize/1.jpg"
                                      , alt = Just "A photo of a dog"
                                      , width = Just 1600
                                      , height = Just 900
                                      }
                                    ]
                            }
                    in
                    Factory.feedViewPostJson overrides
                        |> Decode.decodeString Bluesky.decoder
                        |> Expect.equal (Ok (Factory.feedPost overrides))
            , test "a post with no embed at all decodes to an empty images list" <|
                \_ ->
                    Factory.feedViewPostJson defaultOverrides
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .images
                        |> Expect.equal (Ok [])
            , test "a self-applied label decodes sensitive as True" <|
                \_ ->
                    Factory.feedViewPostJson { defaultOverrides | sensitive = True }
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .sensitive
                        |> Expect.equal (Ok True)
            , test "no labels key at all decodes sensitive as False" <|
                \_ ->
                    Factory.feedViewPostJson defaultOverrides
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map .sensitive
                        |> Expect.equal (Ok False)
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
            , test "an image embed's url/alt become a MediaReference's url/name -- see Components.MediaRenderer, which renders `.name` as an image's alt text" <|
                \_ ->
                    Factory.feedPost
                        { defaultOverrides
                            | images =
                                [ { url = "https://cdn.bsky.app/img/feed_fullsize/1.jpg"
                                  , alt = Just "A photo of a dog"
                                  , width = Just 1600
                                  , height = Just 900
                                  }
                                ]
                        }
                        |> Bluesky.toPost
                        |> .media
                        |> List.map (\media -> ( media.url, media.name ))
                        |> Expect.equal [ ( Just "https://cdn.bsky.app/img/feed_fullsize/1.jpg", Just "A photo of a dog" ) ]
            , test "a feed post with no images leaves Post.media empty" <|
                \_ ->
                    Factory.feedPost defaultOverrides
                        |> Bluesky.toPost
                        |> .media
                        |> Expect.equal []
            , test "toPost strips a sensitive (labeled) post's media down to just the hidden-media placeholder" <|
                \_ ->
                    Factory.feedPost
                        { defaultOverrides
                            | sensitive = True
                            , images =
                                [ { url = "https://cdn.bsky.app/img/feed_fullsize/1.jpg"
                                  , alt = Just "A photo of a dog"
                                  , width = Just 1600
                                  , height = Just 900
                                  }
                                ]
                        }
                        |> Bluesky.toPost
                        |> .media
                        |> List.map .url
                        |> Expect.equal [ Nothing ]
            , test "toPostIncludingSensitiveMedia (BlueskyPostPage's own fetch) keeps a labeled post's real media" <|
                \_ ->
                    Factory.feedPost
                        { defaultOverrides
                            | sensitive = True
                            , images =
                                [ { url = "https://cdn.bsky.app/img/feed_fullsize/1.jpg"
                                  , alt = Just "A photo of a dog"
                                  , width = Just 1600
                                  , height = Just 900
                                  }
                                ]
                        }
                        |> Bluesky.toPostIncludingSensitiveMedia
                        |> .media
                        |> List.map .url
                        |> Expect.equal [ Just "https://cdn.bsky.app/img/feed_fullsize/1.jpg" ]
            ]
        ]
