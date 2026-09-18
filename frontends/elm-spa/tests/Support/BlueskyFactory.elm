module Support.BlueskyFactory exposing (Overrides, defaultOverrides, feedPost, feedViewPostJson)

{-| Test fixtures for `Shared.Federation.Bluesky` -- mirrors `Support.MastodonFactory` exactly:
`feedPost`/`feedViewPostJson` are two views of the same `Overrides` record, so a test can decode
`feedViewPostJson overrides` and compare it against `feedPost overrides` -- see
`Federation.BlueskyTests`' decoder suite.
-}

import Json.Encode as Encode
import Shared.Federation.Bluesky exposing (BlueskyImage, FeedPost)
import Time


{-| A `FeedPost`'s test-relevant fields, all overridable from `defaultOverrides`. `createdAtIso`/
`createdAtMillis` have to be kept in sync by hand -- see `Support.MastodonFactory.Overrides`' own
doc on the reference value both are built from (the same instant, 2023-04-05T12:00:00.000Z).
`images` is `FeedPost`'s own `BlueskyImage` list directly -- AT Proto's `embed.images[]` shape is
already `Maybe`-friendly (`alt` is always a string, never `null`; `aspectRatio` is just omitted when
unknown), so there's no "unset" convention to translate the way `displayName`/`avatar` above need.
-}
type alias Overrides =
    { uri : String
    , text : String
    , createdAtIso : String
    , createdAtMillis : Int
    , isReply : Bool
    , handle : String
    , displayName : Maybe String
    , avatar : Maybe String
    , images : List BlueskyImage
    , sensitive : Bool
    }


defaultOverrides : Overrides
defaultOverrides =
    { uri = "at://did:plc:abc123/app.bsky.feed.post/xyz789"
    , text = "hello bluesky"
    , createdAtIso = "2023-04-05T12:00:00.000Z"
    , createdAtMillis = 1680696000000
    , isReply = False
    , handle = "alice.bsky.social"
    , displayName = Just "Alice"
    , avatar = Just "https://cdn.bsky.app/img/avatar/alice.jpg"
    , images = []
    , sensitive = False
    }


feedPost : Overrides -> FeedPost
feedPost overrides =
    { uri = overrides.uri
    , text = overrides.text
    , createdAt = Time.millisToPosix overrides.createdAtMillis
    , isReply = overrides.isReply
    , authorHandle = overrides.handle
    , authorDisplayName = overrides.displayName
    , authorAvatarUrl = overrides.avatar
    , images = overrides.images
    , sensitive = overrides.sensitive
    }


{-| `reply`/`root`/`parent` refs are left as empty objects when `overrides.isReply` -- `decoder`
only ever checks whether the top-level `"reply"` key is present at all (see its own doc), never
what's inside it, so there's nothing worth fabricating there. `embed` is omitted entirely when
`overrides.images` is empty (a plain text post never carries one at all -- `imagesDecoder`'s own doc
covers why that has to decode to `[]`, not fail), and shaped as a real
`app.bsky.embed.images#view` otherwise. `labels` is a single self-applied adult-content label
(`"sexual"`, an arbitrary real value from AT Proto's own vocab) when `overrides.sensitive`, omitted
otherwise -- `sensitiveDecoder`'s own doc covers why any non-empty `labels` array reads as sensitive,
not just that specific value.
-}
feedViewPostJson : Overrides -> String
feedViewPostJson overrides =
    Encode.encode 0
        (Encode.object
            (( "post"
             , Encode.object
                ([ ( "uri", Encode.string overrides.uri )
                 , ( "cid", Encode.string "bafyreicid" )
                 , ( "author", authorJson overrides )
                 , ( "record"
                   , Encode.object
                        [ ( "$type", Encode.string "app.bsky.feed.post" )
                        , ( "text", Encode.string overrides.text )
                        , ( "createdAt", Encode.string overrides.createdAtIso )
                        ]
                   )
                 , ( "indexedAt", Encode.string overrides.createdAtIso )
                 ]
                    ++ (case overrides.images of
                            [] ->
                                []

                            images ->
                                [ ( "embed"
                                  , Encode.object
                                        [ ( "$type", Encode.string "app.bsky.embed.images#view" )
                                        , ( "images", Encode.list blueskyImageJson images )
                                        ]
                                  )
                                ]
                       )
                    ++ (if overrides.sensitive then
                            [ ( "labels", Encode.list identity [ Encode.object [ ( "val", Encode.string "sexual" ) ] ] ) ]

                        else
                            []
                       )
                )
             )
                :: (if overrides.isReply then
                        [ ( "reply", Encode.object [ ( "root", Encode.object [] ), ( "parent", Encode.object [] ) ] ) ]

                    else
                        []
                   )
            )
        )


blueskyImageJson : BlueskyImage -> Encode.Value
blueskyImageJson image =
    Encode.object
        [ ( "thumb", Encode.string image.url )
        , ( "fullsize", Encode.string image.url )
        , ( "alt", Encode.string (Maybe.withDefault "" image.alt) )
        , ( "aspectRatio"
          , case ( image.width, image.height ) of
                ( Just w, Just h ) ->
                    Encode.object [ ( "width", Encode.int w ), ( "height", Encode.int h ) ]

                _ ->
                    Encode.null
          )
        ]


authorJson : Overrides -> Encode.Value
authorJson overrides =
    Encode.object
        ([ ( "did", Encode.string "did:plc:test" )
         , ( "handle", Encode.string overrides.handle )
         ]
            ++ (overrides.displayName |> Maybe.map (\d -> [ ( "displayName", Encode.string d ) ]) |> Maybe.withDefault [])
            ++ (overrides.avatar |> Maybe.map (\a -> [ ( "avatar", Encode.string a ) ]) |> Maybe.withDefault [])
        )
