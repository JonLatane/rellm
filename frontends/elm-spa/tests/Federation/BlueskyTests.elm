module Federation.BlueskyTests exposing (suite)

import Expect
import Json.Decode as Decode
import Components.Posts as Posts
import Proto.Rellm exposing (defaultPost, unwrapMediaReference, unwrapPost)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Conversions exposing (int64ToInt)
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
                        overrides : Factory.Overrides
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
            , test "decodes likeCount/replyCount -- AT Proto's own real, public, server-aggregated counts" <|
                \_ ->
                    Factory.feedViewPostJson { defaultOverrides | likeCount = 42, replyCount = 7 }
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map (\p -> ( p.likeCount, p.replyCount ))
                        |> Expect.equal (Ok ( 42, 7 ))
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
            , test "likeCount becomes Post.unauthenticatedStarCount -- Bluesky's own real count, not Rellm's anonymized one" <|
                \_ ->
                    Factory.feedPost { defaultOverrides | likeCount = 42 }
                        |> Bluesky.toPost
                        |> .unauthenticatedStarCount
                        |> int64ToInt
                        |> Expect.equal 42
            , test "replyCount becomes both Post.replyCount and .responseCount -- AT Proto has no separate direct/nested distinction to split them across" <|
                \_ ->
                    Factory.feedPost { defaultOverrides | replyCount = 7 }
                        |> Bluesky.toPost
                        |> (\post -> ( post.replyCount, post.responseCount ))
                        |> Expect.equal ( 7, 7 )
            ]
        , describe "route ids"
            [ test "a post's route id is just did~rkey, and its href carries the bare bluesky: host" <|
                \_ ->
                    Posts.postHref "" "rellm.org" "bluesky:jon-latane.bsky.social" { defaultPost | id = "at://did:plc:5q6ck4otnnwuwwxswrzrqnp5/app.bsky.feed.post/3mxywcvomys23" }
                        |> Expect.equal "/post/did:plc:5q6ck4otnnwuwwxswrzrqnp5~3mxywcvomys23@bluesky:"
            , test "the short route id parses back to the full at:// uri" <|
                \_ ->
                    Posts.parsePostRouteId "rellm.org" "did:plc:5q6ck4otnnwuwwxswrzrqnp5~3mxywcvomys23@bluesky:"
                        |> Expect.equal ( "at://did:plc:5q6ck4otnnwuwwxswrzrqnp5/app.bsky.feed.post/3mxywcvomys23", "bluesky:" )
            , test "the older long (percent-encoded uri, handle in the host) route form still parses" <|
                \_ ->
                    Posts.parsePostRouteId "rellm.org" "at%3A%2F%2Fdid%3Aplc%3Aabc%2Fapp.bsky.feed.post%2Fxyz@bluesky:jon-latane.bsky.social"
                        |> Expect.equal ( "at://did:plc:abc/app.bsky.feed.post/xyz", "bluesky:jon-latane.bsky.social" )
            , test "an rkey containing ~ round-trips (only the first ~ separates)" <|
                \_ ->
                    "at://did:plc:abc/app.bsky.feed.post/a~b"
                        |> Bluesky.routeId
                        |> Bluesky.fromRouteId
                        |> Expect.equal "at://did:plc:abc/app.bsky.feed.post/a~b"
            , test "a uri that isn't a post record falls back to the encoded uri, and still round-trips" <|
                \_ ->
                    Posts.parsePostRouteId "rellm.org" (Bluesky.routeId "at://did:plc:abc/app.bsky.feed.generator/xyz" ++ "@bluesky:")
                        |> Expect.equal ( "at://did:plc:abc/app.bsky.feed.generator/xyz", "bluesky:" )
            , test "a Mastodon or Rellm post's href is unchanged" <|
                \_ ->
                    Posts.postHref "" "rellm.org" "mastodon:mastodon.social" { defaultPost | id = "110224857075517327" }
                        |> Expect.equal "/post/110224857075517327@mastodon:mastodon.social"
            ]
        , describe "quoted posts"
            [ test "an app.bsky.embed.record#view embed becomes Post.quotedPost, itself translated like any other post" <|
                \_ ->
                    quotingPostJson
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map (Bluesky.toPost >> .quotedPost >> Maybe.map (unwrapPost >> (\quoted -> ( quoted.content, quoted.id ))))
                        |> Expect.equal (Ok (Just ( Just "quoted text", "at://did:plc:quoted/app.bsky.feed.post/1" )))
            , test "a card (toPost) only goes one quote deep, even though the next level was hydrated too" <|
                \_ ->
                    quotingPostJson
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map (Bluesky.toPost >> .quotedPost >> Maybe.andThen (unwrapPost >> .quotedPost))
                        |> Expect.equal (Ok Nothing)
            , test "a quoted post that was deleted/blocked (no hydrated record) leaves no quotedPost" <|
                \_ ->
                    """{"post":{"uri":"at://did:plc:a/app.bsky.feed.post/2","author":{"handle":"a.bsky.social"},"record":{"text":"hi","createdAt":"2023-04-05T12:00:00.000Z","embed":{"record":{"uri":"at://did:plc:gone/app.bsky.feed.post/9"}}},"embed":{"$type":"app.bsky.embed.record#view","record":{"$type":"app.bsky.embed.record#viewNotFound","uri":"at://did:plc:gone/app.bsky.feed.post/9","notFound":true}}}}"""
                        |> Decode.decodeString Bluesky.decoder
                        |> Result.map (Bluesky.toPost >> .quotedPost)
                        |> Expect.equal (Ok Nothing)
            ]
        ]


{-| A post quoting a post (`quoted text`) that itself quotes a third (`deeper text`), shaped like
`app.bsky.feed.getTimeline`'s `feedViewPost` -- the inner quote is only hydrated one level deep in
`embeds`, same as AT Proto's own AppView.
-}
quotingPostJson : String
quotingPostJson =
    """{"post":{"uri":"at://did:plc:a/app.bsky.feed.post/1","author":{"handle":"a.bsky.social"},"record":{"text":"look at this","createdAt":"2023-04-05T12:00:00.000Z","embed":{"$type":"app.bsky.embed.record","record":{"uri":"at://did:plc:quoted/app.bsky.feed.post/1","cid":"c"}}},"embed":{"$type":"app.bsky.embed.record#view","record":{"$type":"app.bsky.embed.record#viewRecord","uri":"at://did:plc:quoted/app.bsky.feed.post/1","author":{"handle":"quoted.bsky.social","displayName":"Quoted"},"value":{"text":"quoted text","createdAt":"2023-04-05T12:00:00.000Z","embed":{"$type":"app.bsky.embed.record","record":{"uri":"at://did:plc:deeper/app.bsky.feed.post/1","cid":"d"}}},"embeds":[{"$type":"app.bsky.embed.record#view","record":{"$type":"app.bsky.embed.record#viewRecord","uri":"at://did:plc:deeper/app.bsky.feed.post/1","author":{"handle":"deeper.bsky.social"},"value":{"text":"deeper text","createdAt":"2023-04-05T12:00:00.000Z"}}}]}}}}"""
