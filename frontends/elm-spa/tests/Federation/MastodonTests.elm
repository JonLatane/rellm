module Federation.MastodonTests exposing (suite)

import Expect
import Json.Decode as Decode
import Proto.Rellm exposing (unwrapMediaReference)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Federation.Mastodon as Mastodon
import Support.MastodonFactory as Factory exposing (defaultOverrides)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.Federation.Mastodon"
        [ describe "decoder"
            [ test "decodes a real-shaped Status into the same value `toPost` would get directly" <|
                \_ ->
                    Factory.statusJson Factory.defaultOverrides
                        |> Decode.decodeString Mastodon.decoder
                        |> Expect.equal (Ok (Factory.status Factory.defaultOverrides))
            , test "a blank display_name (Mastodon's own \"unset\" convention) decodes to no real name" <|
                \_ ->
                    Factory.statusJson { defaultOverrides | displayName = "" }
                        |> Decode.decodeString Mastodon.decoder
                        |> Result.map .authorDisplayName
                        |> Expect.equal (Ok Nothing)
            , test "a null url decodes to Nothing" <|
                \_ ->
                    Factory.statusJson { defaultOverrides | url = Nothing }
                        |> Decode.decodeString Mastodon.decoder
                        |> Result.map .url
                        |> Expect.equal (Ok Nothing)
            , test "decodes media_attachments, including a null description (Mastodon's own \"no alt text\" convention)" <|
                \_ ->
                    let
                        overrides : Factory.Overrides
                        overrides =
                            { defaultOverrides
                                | mediaAttachments =
                                    [ { id = "1"
                                      , url = "https://mastodon.social/media/1.jpg"
                                      , description = Just "A photo of a cat"
                                      , mediaType = "image"
                                      , width = Just 1200
                                      , height = Just 800
                                      }
                                    , { id = "2"
                                      , url = "https://mastodon.social/media/2.jpg"
                                      , description = Nothing
                                      , mediaType = "image"
                                      , width = Nothing
                                      , height = Nothing
                                      }
                                    ]
                            }
                    in
                    Factory.statusJson overrides
                        |> Decode.decodeString Mastodon.decoder
                        |> Expect.equal (Ok (Factory.status overrides))
            , test "decodes a sensitive status' own flag" <|
                \_ ->
                    Factory.statusJson { defaultOverrides | sensitive = True }
                        |> Decode.decodeString Mastodon.decoder
                        |> Result.map .sensitive
                        |> Expect.equal (Ok True)
            , test "a status with no sensitive key at all decodes to False" <|
                \_ ->
                    Factory.statusJson defaultOverrides
                        |> Decode.decodeString Mastodon.decoder
                        |> Result.map .sensitive
                        |> Expect.equal (Ok False)
            ]
        , describe "toPost"
            [ test "id is the bare status id, unnamespaced -- the synthetic host alongside it (never id alone) is what disambiguates it from a real Rellm post id" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .id
                        |> Expect.equal "110224857075517327"
            , test "is always GLOBALPUBLIC -- a public-timeline Status is definitionally public" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .visibility
                        |> Expect.equal GLOBALPUBLIC
            , test "a top-level status becomes a POST" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .context
                        |> Expect.equal POST
            , test "a status with in_reply_to_id becomes a REPLY" <|
                \_ ->
                    Factory.status { defaultOverrides | inReplyToId = Just "999" }
                        |> Mastodon.toPost "mastodon.social"
                        |> .context
                        |> Expect.equal REPLY
            , test "keeps the account's own HTML content as-is (Mastodon already sanitizes it)" <|
                \_ ->
                    Factory.status { defaultOverrides | content = "<p>hi <strong>there</strong></p>" }
                        |> Mastodon.toPost "mastodon.social"
                        |> .content
                        |> Expect.equal (Just "<p>hi <strong>there</strong></p>")
            , test "carries the author's own avatar as a MediaReference.url, not a Rellm media id" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .author
                        |> Maybe.andThen .avatar
                        |> Maybe.map unwrapMediaReference
                        |> Maybe.andThen .url
                        |> Expect.equal (Just "https://mastodon.social/avatars/alice.png")
            , test "the author's username is qualified with the instance host, mirroring @user@instance" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .author
                        |> Maybe.andThen .username
                        |> Expect.equal (Just "alice@mastodon.social")
            , test "the same account on two different instances (in theory) never gets the same author id" <|
                \_ ->
                    let
                        authorId : String -> Maybe String
                        authorId host =
                            Factory.status Factory.defaultOverrides
                                |> Mastodon.toPost host
                                |> .author
                                |> Maybe.map .userId
                    in
                    Expect.notEqual (authorId "mastodon.social") (authorId "hachyderm.io")
            , test "a media attachment's url/description become a MediaReference's url/name -- see Components.MediaRenderer, which renders `.name` as an image's alt text" <|
                \_ ->
                    Factory.status
                        { defaultOverrides
                            | mediaAttachments =
                                [ { id = "1"
                                  , url = "https://mastodon.social/media/1.jpg"
                                  , description = Just "A photo of a cat"
                                  , mediaType = "image"
                                  , width = Just 1200
                                  , height = Just 800
                                  }
                                ]
                        }
                        |> Mastodon.toPost "mastodon.social"
                        |> .media
                        |> List.map (\media -> ( media.url, media.name ))
                        |> Expect.equal [ ( Just "https://mastodon.social/media/1.jpg", Just "A photo of a cat" ) ]
            , test "an attachment with no media_attachments at all leaves Post.media empty" <|
                \_ ->
                    Factory.status Factory.defaultOverrides
                        |> Mastodon.toPost "mastodon.social"
                        |> .media
                        |> Expect.equal []
            , test "toPost strips a sensitive status' media down to just the hidden-media placeholder" <|
                \_ ->
                    Factory.status
                        { defaultOverrides
                            | sensitive = True
                            , mediaAttachments =
                                [ { id = "1"
                                  , url = "https://mastodon.social/media/1.jpg"
                                  , description = Just "A photo of a cat"
                                  , mediaType = "image"
                                  , width = Just 1200
                                  , height = Just 800
                                  }
                                ]
                        }
                        |> Mastodon.toPost "mastodon.social"
                        |> .media
                        |> List.map .url
                        |> Expect.equal [ Nothing ]
            , test "toPostIncludingSensitiveMedia (MastodonPostPage's own fetch) keeps a sensitive status' real media" <|
                \_ ->
                    Factory.status
                        { defaultOverrides
                            | sensitive = True
                            , mediaAttachments =
                                [ { id = "1"
                                  , url = "https://mastodon.social/media/1.jpg"
                                  , description = Just "A photo of a cat"
                                  , mediaType = "image"
                                  , width = Just 1200
                                  , height = Just 800
                                  }
                                ]
                        }
                        |> Mastodon.toPostIncludingSensitiveMedia "mastodon.social"
                        |> .media
                        |> List.map .url
                        |> Expect.equal [ Just "https://mastodon.social/media/1.jpg" ]
            , test "a non-sensitive status with media is unaffected by the sensitive-media gate" <|
                \_ ->
                    Factory.status
                        { defaultOverrides
                            | sensitive = False
                            , mediaAttachments =
                                [ { id = "1"
                                  , url = "https://mastodon.social/media/1.jpg"
                                  , description = Just "A photo of a cat"
                                  , mediaType = "image"
                                  , width = Just 1200
                                  , height = Just 800
                                  }
                                ]
                        }
                        |> Mastodon.toPost "mastodon.social"
                        |> .media
                        |> List.map .url
                        |> Expect.equal [ Just "https://mastodon.social/media/1.jpg" ]
            , test "two attachments in one status get distinct MediaReference ids (Shared.MediaViewerPanel needs them unique, see Mastodon.toMediaReference's own doc)" <|
                \_ ->
                    Factory.status
                        { defaultOverrides
                            | mediaAttachments =
                                [ { id = "1", url = "https://mastodon.social/media/1.jpg", description = Nothing, mediaType = "image", width = Nothing, height = Nothing }
                                , { id = "2", url = "https://mastodon.social/media/2.jpg", description = Nothing, mediaType = "image", width = Nothing, height = Nothing }
                                ]
                        }
                        |> Mastodon.toPost "mastodon.social"
                        |> .media
                        |> List.map .id
                        |> Expect.equal [ "1", "2" ]
            ]
        ]
