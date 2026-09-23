module Shared.AccountsPanel.MastodonServers exposing
    ( BrowsedMastodonInstance
    , MastodonInstanceInfo
    , browsedMastodonInstanceDecoder
    , encodeBrowsedMastodonInstance
    , fetchMastodonInstanceInfoTask
    )

{-| Everything about a browsed (not connected) Mastodon instance that doesn't need
`Shared.AccountsPanel.Model` itself to make sense: the persisted-list element type
(`BrowsedMastodonInstance`), its encode/decode, and the plain HTTP task/decoder
`Shared.AccountsPanel.update` drives to fill in its logo/display name (`GET /api/v1/instance`). See
`Shared.AccountsPanel.MastodonAccounts` for the sibling module covering _connected_ (OAuth) Mastodon
accounts -- the two used to be one module (`MastodonAccountAndServers`), see that module's own doc
for why they split.

What's deliberately _not_ here, and stays in `Shared.AccountsPanel` itself: the `Model` field this
lives in (`browsedMastodonInstances`), and every `Msg`/`update` case that reacts to user actions and
persists the result.

-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Shared.Federation.Common exposing (jsonResolver, nonEmpty)
import Task exposing (Task)


{-| One Mastodon instance being browsed (see `Shared.AccountsPanel.Model.browsedMastodonInstances`'s
own doc) -- `enabled` mirrors `RellmServer.enabled`: toggled via `UI.mastodonServerFeedChip`'s switch
(`ToggleBrowsedMastodonInstanceEnabled`), it's what `Components.Pages.PostsPage.relevantFeedSources`
checks to decide whether this instance's feed is currently shown, exactly as `enabledServers` does
for a real `RellmServer`. Unlike a `RellmServer`, there's no separate "connected" state to track
alongside it -- browsing needs no connection, so `enabled` alone is the whole story. `logoUrl`/
`displayName` both start `Nothing` and are filled in shortly after, if they resolve, by a follow-up
`fetchMastodonInstanceInfoTask` call -- see `GotMastodonInstanceInfoResult`.
-}
type alias BrowsedMastodonInstance =
    { host : String
    , enabled : Bool
    , logoUrl : Maybe String
    , displayName : Maybe String
    , sortOrder : Int
    }


encodeBrowsedMastodonInstance : BrowsedMastodonInstance -> Encode.Value
encodeBrowsedMastodonInstance instance =
    Encode.object
        [ ( "host", Encode.string instance.host )
        , ( "enabled", Encode.bool instance.enabled )
        , ( "logoUrl", instance.logoUrl |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "displayName", instance.displayName |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "sortOrder", Encode.int instance.sortOrder )
        ]


browsedMastodonInstanceDecoder : Decoder BrowsedMastodonInstance
browsedMastodonInstanceDecoder =
    Decode.map5 BrowsedMastodonInstance
        (Decode.field "host" Decode.string)
        (Decode.field "enabled" Decode.bool)
        (Decode.maybe (Decode.field "logoUrl" Decode.string))
        (Decode.maybe (Decode.field "displayName" Decode.string))
        sortOrderDecoder


{-| `fetchMastodonInstanceInfoTask`'s result -- `logoUrl` (from `thumbnail`) and `displayName` (from
`title`) both `Nothing` if blank/absent, the same as a Rellm server with no logo/name configured.
-}
type alias MastodonInstanceInfo =
    { logoUrl : Maybe String
    , displayName : Maybe String
    }


{-| `GET /api/v1/instance` against `host` -- a public, unauthenticated Mastodon REST endpoint (same
"no auth needed" reasoning as `Shared.Federation.Mastodon.fetchPosts`), fetched once when an instance
is added to `browsedMastodonInstances` (see `BrowseMastodonInstanceClicked`/
`GotMastodonInstanceInfoResult`) to get its `thumbnail`/`title` -- the small instance logo image and
display name shown in `UI.mastodonServerFeedChip`.
-}
fetchMastodonInstanceInfoTask : String -> Task Http.Error MastodonInstanceInfo
fetchMastodonInstanceInfoTask host =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ host ++ "/api/v1/instance"
        , body = Http.emptyBody
        , resolver =
            jsonResolver instanceInfoDecoder
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


instanceInfoDecoder : Decode.Decoder MastodonInstanceInfo
instanceInfoDecoder =
    Decode.map2 MastodonInstanceInfo
        (Decode.maybe (Decode.field "thumbnail" Decode.string))
        (Decode.maybe (Decode.field "title" Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
