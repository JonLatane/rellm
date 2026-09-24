module Support.MastodonFactory exposing (Overrides, defaultOverrides, status, statusJson)

{-| Test fixtures for `Shared.Federation.Mastodon` -- `status`/`statusJson` are two views of the
same `Overrides` record (a decoded `Status` value, and the raw Mastodon API JSON it would have come
from), so a test can build one `Overrides`, feed `statusJson` through `Mastodon.decoder`, and compare
the result against `status` of the same overrides -- see `Federation.MastodonTests`' decoder suite.
-}

import Json.Encode as Encode
import Shared.Federation.Mastodon exposing (MediaAttachment, Status)
import Time


{-| A `Status`'s test-relevant fields, all overridable from `defaultOverrides`. `createdAtIso`/
`createdAtMillis` have to be kept in sync by hand (nothing derives one from the other) -- see
`defaultOverrides`' own doc for the reference value both start from. `displayName`/`avatar` are
plain (non-`Maybe`) strings, matching Mastodon's real API shape (always present, `""` for "unset"
rather than the key being absent or `null`) -- `status`/`statusJson` are what translate that into
`Status`'s own `Maybe String` fields. `mediaAttachments` is `Status`'s own `MediaAttachment` list
directly, unlike those -- Mastodon's real `description`/`meta` shapes are already `Maybe`-friendly
(see `mediaAttachmentJson`'s own doc), so there's no analogous "unset" convention to translate here.
-}
type alias Overrides =
    { id : String
    , url : Maybe String
    , content : String
    , createdAtIso : String
    , createdAtMillis : Int
    , inReplyToId : Maybe String
    , username : String
    , displayName : String
    , avatar : String
    , mediaAttachments : List MediaAttachment
    , sensitive : Bool
    , favouritesCount : Int
    , repliesCount : Int
    }


{-| `createdAtIso`/`createdAtMillis` are the same instant, 2023-04-05T12:00:00.000Z -- verified by
hand (94 days after 2023-01-01T00:00:00Z's well-known 1672531200, plus 12h): 1672531200 + 94_86400 +
12_3600 = 1680696000 seconds = 1680696000000 ms.
-}
defaultOverrides : Overrides
defaultOverrides =
    { id = "110224857075517327"
    , url = Just "https://mastodon.social/@alice/110224857075517327"
    , content = "<p>Hello world</p>"
    , createdAtIso = "2023-04-05T12:00:00.000Z"
    , createdAtMillis = 1680696000000
    , inReplyToId = Nothing
    , username = "alice"
    , displayName = "Alice Example"
    , avatar = "https://mastodon.social/avatars/alice.png"
    , mediaAttachments = []
    , sensitive = False
    , favouritesCount = 0
    , repliesCount = 0
    }


status : Overrides -> Status
status overrides =
    { id = overrides.id
    , url = overrides.url
    , content = overrides.content
    , createdAt = Time.millisToPosix overrides.createdAtMillis
    , inReplyToId = overrides.inReplyToId
    , authorUsername = overrides.username
    , authorDisplayName = nonEmpty overrides.displayName
    , authorAvatarUrl = nonEmpty overrides.avatar
    , mediaAttachments = overrides.mediaAttachments
    , sensitive = overrides.sensitive
    , favouritesCount = overrides.favouritesCount
    , repliesCount = overrides.repliesCount
    }


nonEmpty : String -> Maybe String
nonEmpty s =
    if String.isEmpty s then
        Nothing

    else
        Just s


statusJson : Overrides -> String
statusJson overrides =
    Encode.encode 0
        (Encode.object
            [ ( "id", Encode.string overrides.id )
            , ( "url", overrides.url |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
            , ( "content", Encode.string overrides.content )
            , ( "created_at", Encode.string overrides.createdAtIso )
            , ( "in_reply_to_id", overrides.inReplyToId |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
            , ( "account"
              , Encode.object
                    [ ( "username", Encode.string overrides.username )
                    , ( "display_name", Encode.string overrides.displayName )
                    , ( "avatar", Encode.string overrides.avatar )
                    ]
              )
            , ( "media_attachments", Encode.list mediaAttachmentJson overrides.mediaAttachments )
            , ( "sensitive", Encode.bool overrides.sensitive )
            , ( "favourites_count", Encode.int overrides.favouritesCount )
            , ( "replies_count", Encode.int overrides.repliesCount )
            ]
        )


{-| A `MediaAttachment`'s real Mastodon JSON shape -- `description`, unlike `display_name`/`avatar`
above, really is `null` (not `""`/absent) for "no alt text" on the live API, so this mirrors that
directly rather than going through `nonEmpty`/`Encode.null`'s `Maybe.withDefault` trick those use.
`meta.original.width`/`height` are similarly genuinely optional (omitted, not `0`, when Mastodon
hasn't determined them) -- `List.filterMap identity` drops each one from the encoded object rather
than encoding a placeholder.
-}
mediaAttachmentJson : MediaAttachment -> Encode.Value
mediaAttachmentJson attachment =
    Encode.object
        [ ( "id", Encode.string attachment.id )
        , ( "url", Encode.string attachment.url )
        , ( "description", attachment.description |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "type", Encode.string attachment.mediaType )
        , ( "meta"
          , Encode.object
                [ ( "original"
                  , Encode.object
                        (List.filterMap identity
                            [ attachment.width |> Maybe.map (\w -> ( "width", Encode.int w ))
                            , attachment.height |> Maybe.map (\h -> ( "height", Encode.int h ))
                            ]
                        )
                  )
                ]
          )
        ]
