module Shared.Federation.Mastodon exposing
    ( Account
    , Status
    , decoder
    , fetchAccountStatuses
    , fetchFollowers
    , fetchFollowing
    , fetchPosts
    , fetchStatus
    , lookupAccount
    , searchAccounts
    , toPost
    )

{-| Translates Mastodon's REST API into Rellm's `Post` shape, entirely client-side -- see
`Ports.facebookLoginPopup`'s `"mastodon"` provider doc and `Shared.MastodonAccount`'s
own doc for the connection side this feeds off of. `fetchPosts` is called from
`Components.Pages.PostsPage.fetchFeedSource`'s `MastodonInstance` case -- see `FeedSource`'s own doc
for how a Mastodon instance's feed is fetched/stored/animated alongside a real Rellm server's.
`fetchStatus` is the single-post equivalent, called from `Components.Pages.PostPage.init` when a
route's post id parses as `Components.Posts.MastodonPostId` -- viewing one post directly, rather than
browsing a timeline, needs no Rellm server involved at all.

`Account`/`lookupAccount`/`fetchAccountStatuses`/`fetchFollowers`/`fetchFollowing` back
`Components.Pages.MastodonUserProfilePage`/`MastodonUsersPage` -- unlike everything else here, these
resolve a specific *account*, not a timeline, so a viewed profile's own posts/followers/following can
be shown rather than just a whole instance's local timeline. All still unauthenticated: Mastodon's
public API serves an unlocked account's own profile/statuses/followers/following with no token at
all, same as `fetchPosts`/`fetchStatus` already rely on for the local timeline/single-status case.
-}

import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Proto.Rellm exposing (Author, Post, defaultAuthor, defaultMediaReference, defaultPost, wrapMediaReference)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Conversions exposing (posixToTimestamp)
import Shared.Federation.Common exposing (jsonResolver, nonEmpty)
import Task exposing (Task)
import Time
import Url


{-| Just the fields of Mastodon's `Status` entity (one element of
`GET /api/v1/timelines/public`'s response array) that `toPost` actually needs -- see
<https://docs.joinmastodon.org/entities/Status/>.
-}
type alias Status =
    { id : String
    , url : Maybe String
    , content : String
    , createdAt : Time.Posix
    , inReplyToId : Maybe String
    , authorUsername : String
    , authorDisplayName : Maybe String
    , authorAvatarUrl : Maybe String
    }


decoder : Decoder Status
decoder =
    Decode.map8 Status
        (Decode.field "id" Decode.string)
        (Decode.maybe (Decode.field "url" Decode.string))
        (Decode.field "content" Decode.string)
        (Decode.field "created_at" Iso8601.decoder)
        (Decode.maybe (Decode.field "in_reply_to_id" Decode.string))
        (Decode.at [ "account", "username" ] Decode.string)
        (Decode.at [ "account", "display_name" ] Decode.string |> Decode.map nonEmpty)
        (Decode.at [ "account", "avatar" ] Decode.string |> Decode.map nonEmpty)


{-| A `Status`'s translation into a Rellm `Post` -- `id` is just Mastodon's own bare `status.id`
(a numeric string), *not* further namespaced with `instanceHost` the way it briefly was: a federated
post's own `id` is never used or compared on its own anywhere in this app, always alongside its
synthetic host (`Components.Pages.PostsPage.feedSourceKey`'s own `"mastodon:" ++ instanceHost`, or
`Components.Posts.postHref`'s own `id@host` route) -- see `Components.Posts.parseFederatedPostId`,
which reconstructs `instanceHost` from *that* host string rather than from `id` itself. Keeping `id`
bare avoids doubly encoding the same instance host in both halves of a `/post/id@host` URL. `content`
is left as Mastodon's own sanitized HTML (Mastodon strips dangerous tags server-side before ever
serving it back), not converted to/from Markdown -- `Components.Markdown.view` (every render site's
own path for `Post.content`) detects that and renders it as HTML directly rather than misreading it
as Markdown source, see its own doc. `visibility` is always `GLOBALPUBLIC`: a `Status` fetched off a
public timeline endpoint is definitionally public. `author.avatar` uses `MediaReference.url` (see
that field's own doc in `protos/media.proto`) rather than `id`, since this avatar isn't and never
will be Rellm-hosted media.
-}
toPost : String -> Status -> Post
toPost instanceHost status =
    { defaultPost
        | id = status.id
        , author = Just (toAuthor instanceHost status)
        , content = Just status.content
        , link = status.url
        , context =
            if status.inReplyToId /= Nothing then
                REPLY

            else
                POST
        , visibility = GLOBALPUBLIC
        , createdAt = Just (posixToTimestamp status.createdAt)
        , lastActivityAt = Just (posixToTimestamp status.createdAt)
    }


{-| `GET /api/v1/timelines/public?local=true&limit=20` -- the local (this-instance-only) public
timeline, unauthenticated, already translated via `toPost`. `local=true` rather than the federated
(whole-known-network) timeline, since connecting one instance shouldn't implicitly pull in every
server it happens to federate with too -- mirrors Rellm's own `ALL_ACCESSIBLE_POSTS` being scoped
to *this* server's own posts, not every server it's federated with either.
-}
fetchPosts : String -> Task Http.Error (List Post)
fetchPosts instanceHost =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/timelines/public?local=true&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.list decoder) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map (toPost instanceHost))


{-| `GET /api/v1/statuses/:id` -- a single status, by id, unauthenticated (same public-endpoint
reasoning as `fetchPosts`), already translated via `toPost`. Unlike `fetchPosts`, this works
regardless of whether `local=true` would apply -- a direct id lookup isn't scoped to "this instance's
own timeline" the way browsing one is.
-}
fetchStatus : String -> String -> Task Http.Error Post
fetchStatus instanceHost statusId =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/statuses/" ++ statusId
        , body = Http.emptyBody
        , resolver = jsonResolver decoder (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (toPost instanceHost)


toAuthor : String -> Status -> Author
toAuthor instanceHost status =
    { defaultAuthor
        | userId = "mastodon:" ++ instanceHost ++ ":" ++ status.authorUsername
        , username = Just (status.authorUsername ++ "@" ++ instanceHost)
        , realName = status.authorDisplayName
        , avatar = status.authorAvatarUrl |> Maybe.map (\url -> wrapMediaReference { defaultMediaReference | url = Just url })
    }


{-| Just the fields of Mastodon's `Account` entity that `MastodonUserProfilePage`/`MastodonUsersPage`
need -- see <https://docs.joinmastodon.org/entities/Account/>. `id` is this instance's own internal
account id (opaque, instance-specific -- never shown, only threaded back into
`fetchAccountStatuses`/`fetchFollowers`/`fetchFollowing`), distinct from `username` (the handle a
person actually types/sees, and what `MastodonUserProfilePage`'s own route is keyed by -- see
`Components.Users.parseFederatedUserId`).
-}
type alias Account =
    { id : String
    , username : String
    , displayName : Maybe String
    , note : Maybe String
    , avatarUrl : Maybe String
    , followersCount : Int
    , followingCount : Int
    , statusesCount : Int

    -- Whether this account approves followers manually -- when `True`, `fetchFollowers`/
    -- `fetchFollowing` come back an empty list (not an error) unless the requester is
    -- authenticated as this account or one it's approved, since Mastodon treats a locked
    -- account's own relationship lists as private. Lets `Components.Pages.UsersPage` show "this
    -- account's followers/following are private" instead of a misleading "nobody here yet" for
    -- that specific, common case.
    , locked : Bool
    }


accountDecoder : Decoder Account
accountDecoder =
    Decode.map8
        (\id username displayName note avatarUrl followersCount followingCount statusesCount locked ->
            { id = id
            , username = username
            , displayName = displayName
            , note = note
            , avatarUrl = avatarUrl
            , followersCount = followersCount
            , followingCount = followingCount
            , statusesCount = statusesCount
            , locked = locked
            }
        )
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)
        (Decode.field "display_name" Decode.string |> Decode.map nonEmpty)
        (Decode.field "note" Decode.string |> Decode.map nonEmpty)
        (Decode.field "avatar" Decode.string |> Decode.map nonEmpty)
        (Decode.field "followers_count" Decode.int)
        (Decode.field "following_count" Decode.int)
        (Decode.field "statuses_count" Decode.int)
        |> Decode.andThen (\f -> Decode.map f (Decode.oneOf [ Decode.field "locked" Decode.bool, Decode.succeed False ]))


{-| `GET /api/v1/accounts/lookup?acct=username` -- resolves a bare Mastodon username (as it appears
in a route, or as typed into a search box) to its full `Account` on `instanceHost`, unauthenticated.
The one call every one of `MastodonUserProfilePage`'s other fetches (`fetchAccountStatuses`/
`fetchFollowers`/`fetchFollowing`) depends on first, since those all key off `Account.id`, not the
username itself.
-}
lookupAccount : String -> String -> Task Http.Error Account
lookupAccount instanceHost username =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/accounts/lookup?acct=" ++ Url.percentEncode username
        , body = Http.emptyBody
        , resolver = jsonResolver accountDecoder (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /api/v1/accounts/:id/statuses` -- `accountId`'s own authored posts (`exclude_replies`/
`exclude_reblogs`, so a profile's post list reads like Mastodon's own "Posts" tab rather than "Posts
and replies," and skips bare boosts, which carry no `content` of their own for `toPost` to show --
`Status.reblog` nests the original post's own content separately, which this doesn't bother
following), already translated via `toPost`. Unlike `fetchPosts`' local timeline, this is one
specific account's posts regardless of which instance the *viewer* is on -- exactly what
`MastodonUserProfilePage`'s embedded `Components.Pages.PostsPage` needs (see that module's own
`MastodonAccountFeed` `FeedSource`).
-}
fetchAccountStatuses : String -> String -> Task Http.Error (List Post)
fetchAccountStatuses instanceHost accountId =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/accounts/" ++ accountId ++ "/statuses?exclude_replies=true&exclude_reblogs=true&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.list decoder) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map (toPost instanceHost))


{-| `GET /api/v1/accounts/:id/followers` -- up to 40 of `accountId`'s followers, unauthenticated (an
unlocked account's follower list is public Mastodon API data, same as its profile/statuses). Returns
an empty list, not an error, for a *locked* account's followers/following when the requester isn't
authenticated as that account or one it approved -- see `Account.locked`'s own doc; there's currently
no way to distinguish "genuinely has none" from "locked" in `Components.Pages.UsersPage`'s rendering,
an accepted first-pass limitation. No pagination beyond the first 40 either, mirroring
`Components.Pages.UsersPage`'s own lack of pagination for Rellm's real `GetUsers` RPC.
-}
fetchFollowers : String -> String -> Task Http.Error (List Account)
fetchFollowers instanceHost accountId =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/accounts/" ++ accountId ++ "/followers?limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.list accountDecoder) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /api/v1/accounts/:id/following` -- `fetchFollowers`'s own doc, just the other direction.
-}
fetchFollowing : String -> String -> Task Http.Error (List Account)
fetchFollowing instanceHost accountId =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v1/accounts/" ++ accountId ++ "/following?limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.list accountDecoder) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /api/v2/search?type=accounts&q=...` -- Mastodon's own account search against `instanceHost`,
unauthenticated (works on most instances for a plain text query; `resolve=true` would additionally
try a remote webfinger lookup for an exact `user@host` query, not requested here since
`Components.Pages.UsersPage`'s own People-page search is about discovering matching accounts by
name, not resolving one already-known handle -- that's what `lookupAccount` is for). Backs
`UsersPage`'s own unfiltered listing once a search is typed in, fanned out across every
browsed/connected Mastodon instance the same way `Components.Pages.PostsPage.mastodonHostsToFetch`
already does for post search.
-}
searchAccounts : String -> String -> Task Http.Error (List Account)
searchAccounts instanceHost query =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://" ++ instanceHost ++ "/api/v2/search?type=accounts&limit=20&q=" ++ Url.percentEncode query
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "accounts" (Decode.list accountDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
