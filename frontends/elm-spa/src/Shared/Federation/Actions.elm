module Shared.Federation.Actions exposing
    ( ServerAccount(..)
    , accountId
    , avatarUrlOf
    , createPost
    , hostOf
    , postWebUrl
    , usableAccounts
    , deletePost
    , MastodonProfileTarget
    , editPost
    , fetchBlueskyFollowState
    , fetchBlueskyOwnProfile
    , fetchMastodonFollowState
    , isOwnBlueskyProfile
    , setBlueskyFollowing
    , updateBlueskyOwnProfile
    , fetchMastodonOwnProfile
    , isOwnMastodonProfile
    , setMastodonFollowing
    , updateMastodonOwnProfile
    , isOwnPost
    , ownAccountFor
    , reply
    , rotatedBluesky
    , rotatedMastodon
    , serverAccountFor
    , usernameOf
    , writeErrorText
    )

{-| Writing to Mastodon/Bluesky as a connected account -- replying to, editing and deleting posts -- the
write counterpart to the reads in `Shared.Federation.Mastodon`/`Bluesky`. Every task resolves to the
`AccountsPanel.Msg` to forward if the account's token had to be refreshed on the way (see
`MastodonAccounts.performWithMastodonAccount`/`BlueskyAccounts.performWithBlueskyAccount`).
-}

import Http
import Proto.Rellm exposing (Post)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.MastodonAccounts as MastodonAccounts exposing (MastodonAccount)
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Mastodon as Mastodon exposing (MastodonVisibility)
import Task exposing (Task)


type ServerAccount
    = MastodonServerAccount MastodonAccount
    | BlueskyServerAccount BlueskyAccount


{-| The connected account (if any) that acts on `host` (`"mastodon:" ++ instance` / `"bluesky:"`): a Mastodon
`host` prefers an account on that very instance (a status id is only meaningful to the instance it came from)
but otherwise falls back to the first usable one -- `reply` then resolves the post onto that account's own
instance; a Bluesky one needs the enabled account. Accounts flagged `needsReauth` don't count.
-}
serverAccountFor : AccountsPanel.Model -> String -> Maybe ServerAccount
serverAccountFor accountsPanelModel host =
    if String.startsWith "mastodon:" host then
        let
            usable : List MastodonAccount
            usable =
                List.filter (not << .needsReauth) accountsPanelModel.mastodonAccounts
        in
        usable
            |> List.filter (\account -> account.instanceHost == String.dropLeft 9 host)
            |> List.head
            |> orElse (List.head usable)
            |> Maybe.map MastodonServerAccount

    else if String.startsWith "bluesky:" host then
        accountsPanelModel.blueskyAccounts
            |> List.filter (\account -> account.enabled && not account.needsReauth)
            |> List.head
            |> Maybe.map BlueskyServerAccount

    else
        Nothing


orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback maybe =
    case maybe of
        Just _ ->
            maybe

        Nothing ->
            fallback


{-| Whether `post` (seen on `host`) was written by `account`. A Mastodon status can only be edited/deleted
through the instance it lives on, so viewing one through another instance is never "own".
-}
isOwnPost : ServerAccount -> String -> Post -> Bool
isOwnPost account host post =
    let
        authorName : Maybe String
        authorName =
            post.author |> Maybe.andThen .username |> Maybe.map String.toLower
    in
    case account of
        MastodonServerAccount a ->
            host == "mastodon:" ++ a.instanceHost && authorName == Just (String.toLower (a.username ++ "@" ++ a.instanceHost))

        BlueskyServerAccount a ->
            host == "bluesky:" && authorName == Just (String.toLower a.handle)


{-| The usable connected account `post` belongs to, if any -- who edits/deletes it.
-}
ownAccountFor : AccountsPanel.Model -> String -> Post -> Maybe ServerAccount
ownAccountFor accountsPanelModel host post =
    let
        candidates : List ServerAccount
        candidates =
            if String.startsWith "mastodon:" host then
                accountsPanelModel.mastodonAccounts |> List.filter (not << .needsReauth) |> List.map MastodonServerAccount

            else if String.startsWith "bluesky:" host then
                accountsPanelModel.blueskyAccounts |> List.filter (\a -> a.enabled && not a.needsReauth) |> List.map BlueskyServerAccount

            else
                []
    in
    candidates |> List.filter (\account -> isOwnPost account host post) |> List.head


usernameOf : ServerAccount -> String
usernameOf account =
    case account of
        MastodonServerAccount a ->
            a.username

        BlueskyServerAccount a ->
            a.handle


avatarUrlOf : ServerAccount -> Maybe String
avatarUrlOf account =
    case account of
        MastodonServerAccount a ->
            a.avatarUrl

        BlueskyServerAccount a ->
            a.avatarUrl


rotatedMastodon : MastodonAccount -> MastodonAccount -> Maybe AccountsPanel.Msg
rotatedMastodon before after =
    if after.accessToken == before.accessToken then
        Nothing

    else
        Just (AccountsPanel.MastodonAccountRefreshed after)


rotatedBluesky : BlueskyAccount -> BlueskyAccount -> Maybe AccountsPanel.Msg
rotatedBluesky before after =
    if after.accessToken == before.accessToken then
        Nothing

    else
        Just (AccountsPanel.BlueskyAccountRefreshed after)


{-| Replies to `post` (seen on `host`) as `account`. `visibility` only matters for Mastodon.
-}
reply : ServerAccount -> String -> Post -> MastodonVisibility -> String -> Task Http.Error (Maybe AccountsPanel.Msg)
reply account host post visibility text =
    case account of
        MastodonServerAccount a ->
            MastodonAccounts.performWithMastodonAccount a
                (\token ->
                    (if host == "mastodon:" ++ a.instanceHost then
                        Task.succeed post.id

                     else
                        case post.link of
                            Just url ->
                                Mastodon.resolveStatusId a.instanceHost token url

                            Nothing ->
                                Task.fail (Http.BadStatus 404)
                    )
                        |> Task.andThen
                            (\parentId ->
                                Mastodon.postStatus a.instanceHost token { text = text, inReplyToId = Just parentId, visibility = visibility }
                                    |> Task.map (\_ -> ())
                            )
                )
                |> Task.map (\( refreshed, () ) -> rotatedMastodon a refreshed)

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\auth -> Bluesky.createReply a.handle auth post.id text)
                |> Task.map (\( refreshed, () ) -> rotatedBluesky a refreshed)


{-| Replaces `post`'s text as its own `account`.
-}
editPost : ServerAccount -> Post -> String -> Task Http.Error (Maybe AccountsPanel.Msg)
editPost account post text =
    case account of
        MastodonServerAccount a ->
            MastodonAccounts.performWithMastodonAccount a (\token -> Mastodon.editStatus a.instanceHost token post.id text)
                |> Task.map (\( refreshed, () ) -> rotatedMastodon a refreshed)

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\auth -> Bluesky.editPost a.handle auth post.id text)
                |> Task.map (\( refreshed, () ) -> rotatedBluesky a refreshed)


deletePost : ServerAccount -> Post -> Task Http.Error (Maybe AccountsPanel.Msg)
deletePost account post =
    case account of
        MastodonServerAccount a ->
            MastodonAccounts.performWithMastodonAccount a (\token -> Mastodon.deleteStatus a.instanceHost token post.id)
                |> Task.map (\( refreshed, () ) -> rotatedMastodon a refreshed)

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\auth -> Bluesky.deletePost a.handle auth post.id)
                |> Task.map (\( refreshed, () ) -> rotatedBluesky a refreshed)


{-| A human-readable reason for a failed write -- notably a Mastodon 403 (a token connected before
`write:statuses` was requested) tells the user to reconnect.
-}
writeErrorText : Http.Error -> String
writeErrorText err =
    case err of
        Http.BadStatus 403 ->
            "Not allowed. If this is a Mastodon account connected before this permission (posting, following, profile editing) was requested, disconnect and reconnect it to grant it."

        Http.BadStatus 401 ->
            "Your account was signed out. Reconnect it in the Accounts Panel."

        Http.BadStatus status ->
            "The server rejected that (error " ++ String.fromInt status ++ ")."

        Http.NetworkError ->
            "Couldn't reach the server."

        Http.Timeout ->
            "The server took too long to respond."

        Http.BadUrl _ ->
            "Bad address."

        Http.BadBody _ ->
            if BlueskyAccounts.isReauthError err || MastodonAccounts.isReauthError err then
                "Your account needs to be reconnected in the Accounts Panel."

            else
                "Unexpected response from the server."


{-| Every connected account that can post right now: Mastodon accounts not flagged `needsReauth`, and the enabled
Bluesky ones.
-}
usableAccounts : AccountsPanel.Model -> List ServerAccount
usableAccounts accountsPanelModel =
    (accountsPanelModel.mastodonAccounts |> List.filter (not << .needsReauth) |> List.map MastodonServerAccount)
        ++ (accountsPanelModel.blueskyAccounts |> List.filter (\a -> a.enabled && not a.needsReauth) |> List.map BlueskyServerAccount)


{-| A stable id for picking an account in a `<select>` -- distinct from every `RellmAccounts.rellmAccountId`.
-}
accountId : ServerAccount -> String
accountId account =
    case account of
        MastodonServerAccount a ->
            "mastodon:" ++ a.instanceHost ++ "/" ++ a.username

        BlueskyServerAccount a ->
            "bluesky:" ++ a.handle


{-| The `"mastodon:" ++ instance` / `"bluesky:"` host tag the account's posts live under -- see
`Components.Posts.isFederatedHost`.
-}
hostOf : ServerAccount -> String
hostOf account =
    case account of
        MastodonServerAccount a ->
            "mastodon:" ++ a.instanceHost

        BlueskyServerAccount _ ->
            "bluesky:"


{-| A new top-level post (not a reply) as `account`, resolving to the `AccountsPanel.Msg` to forward for a token
refresh and the new post's public web URL, if known. `visibility` only matters for Mastodon.
-}
createPost : ServerAccount -> MastodonVisibility -> String -> Task Http.Error ( Maybe AccountsPanel.Msg, Maybe String )
createPost account visibility text =
    case account of
        MastodonServerAccount a ->
            MastodonAccounts.performWithMastodonAccount a
                (\token -> Mastodon.postStatus a.instanceHost token { text = text, inReplyToId = Nothing, visibility = visibility })
                |> Task.map (\( refreshed, url ) -> ( rotatedMastodon a refreshed, url ))

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\auth -> Bluesky.createPost a.handle auth text)
                |> Task.map (\( refreshed, uri ) -> ( rotatedBluesky a refreshed, Just (postWebUrl a.handle uri) ))


{-| `https://bsky.app/profile/{handle}/post/{rkey}` for the post record at `uri`.
-}
postWebUrl : String -> String -> String
postWebUrl handle uri =
    "https://bsky.app/profile/" ++ handle ++ "/post/" ++ (uri |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault "")


{-| A Mastodon profile being viewed: the instance it lives on, its bare `username`, and its account id there.
-}
type alias MastodonProfileTarget =
    { instanceHost : String
    , username : String
    , accountId : String
    }


{-| Whether `account` is the very account `target` is the profile of.
-}
isOwnMastodonProfile : MastodonAccount -> MastodonProfileTarget -> Bool
isOwnMastodonProfile account target =
    account.instanceHost == target.instanceHost && String.toLower account.username == String.toLower target.username


{-| `target`'s account id on `account`'s own instance -- the same id when it lives there, otherwise looked up
(federating it in if need be).
-}
targetIdOn : MastodonAccount -> String -> MastodonProfileTarget -> Task Http.Error String
targetIdOn account token target =
    if account.instanceHost == target.instanceHost then
        Task.succeed target.accountId

    else
        Mastodon.resolveAccountId account.instanceHost token (target.username ++ "@" ++ target.instanceHost)


{-| How `account` currently relates to `target` (following / follow requested).
-}
fetchMastodonFollowState : MastodonAccount -> MastodonProfileTarget -> Task Http.Error ( Maybe AccountsPanel.Msg, Mastodon.Relationship )
fetchMastodonFollowState account target =
    MastodonAccounts.performWithMastodonAccount account
        (\token ->
            targetIdOn account token target
                |> Task.andThen (Mastodon.fetchRelationship account.instanceHost token)
        )
        |> Task.map (\( refreshed, relationship ) -> ( rotatedMastodon account refreshed, relationship ))


{-| Has `account` follow (`True`) or unfollow (`False`) `target`.
-}
setMastodonFollowing : Bool -> MastodonAccount -> MastodonProfileTarget -> Task Http.Error ( Maybe AccountsPanel.Msg, Mastodon.Relationship )
setMastodonFollowing follow account target =
    MastodonAccounts.performWithMastodonAccount account
        (\token ->
            targetIdOn account token target
                |> Task.andThen (Mastodon.setFollowing follow account.instanceHost token)
        )
        |> Task.map (\( refreshed, relationship ) -> ( rotatedMastodon account refreshed, relationship ))


{-| `account`'s current display name and plain-text bio, to start editing its profile from.
-}
fetchMastodonOwnProfile : MastodonAccount -> Task Http.Error ( Maybe AccountsPanel.Msg, Mastodon.OwnProfile )
fetchMastodonOwnProfile account =
    MastodonAccounts.performWithMastodonAccount account (Mastodon.fetchOwnProfile account.instanceHost)
        |> Task.map (\( refreshed, profile ) -> ( rotatedMastodon account refreshed, profile ))


{-| Saves a new display name and bio on `account`'s own profile.
-}
updateMastodonOwnProfile : MastodonAccount -> Mastodon.OwnProfile -> Task Http.Error (Maybe AccountsPanel.Msg)
updateMastodonOwnProfile account profile =
    MastodonAccounts.performWithMastodonAccount account (\token -> Mastodon.updateOwnProfile account.instanceHost token profile)
        |> Task.map (\( refreshed, () ) -> rotatedMastodon account refreshed)


{-| Whether `account` is the very account whose profile is `viewedHandle`.
-}
isOwnBlueskyProfile : BlueskyAccount -> String -> Bool
isOwnBlueskyProfile account viewedHandle =
    String.toLower account.handle == String.toLower viewedHandle


{-| Whether `account` follows `viewedHandle`, and the ids needed to (un)follow.
-}
fetchBlueskyFollowState : BlueskyAccount -> String -> Task Http.Error ( Maybe AccountsPanel.Msg, Bluesky.FollowState )
fetchBlueskyFollowState account viewedHandle =
    BlueskyAccounts.performWithBlueskyAccount account (\auth -> Bluesky.fetchFollowState auth viewedHandle)
        |> Task.map (\( refreshed, state ) -> ( rotatedBluesky account refreshed, state ))


{-| Has `account` follow (`True`) or unfollow (`False`) the actor in `state`.
-}
setBlueskyFollowing : Bool -> BlueskyAccount -> Bluesky.FollowState -> Task Http.Error ( Maybe AccountsPanel.Msg, Bluesky.FollowState )
setBlueskyFollowing follow account state =
    BlueskyAccounts.performWithBlueskyAccount account (\auth -> Bluesky.setFollowing follow account.handle auth state)
        |> Task.map (\( refreshed, newState ) -> ( rotatedBluesky account refreshed, newState ))


{-| `account`'s current profile record, to start editing its profile from.
-}
fetchBlueskyOwnProfile : BlueskyAccount -> Task Http.Error ( Maybe AccountsPanel.Msg, Bluesky.OwnProfileRecord )
fetchBlueskyOwnProfile account =
    BlueskyAccounts.performWithBlueskyAccount account (\auth -> Bluesky.fetchOwnProfileRecord account.handle auth)
        |> Task.map (\( refreshed, record ) -> ( rotatedBluesky account refreshed, record ))


{-| Saves a new display name and bio on `account`'s own profile record.
-}
updateBlueskyOwnProfile : BlueskyAccount -> Bluesky.OwnProfileRecord -> { displayName : String, description : String } -> Task Http.Error (Maybe AccountsPanel.Msg)
updateBlueskyOwnProfile account record edit =
    BlueskyAccounts.performWithBlueskyAccount account (\auth -> Bluesky.updateOwnProfileRecord account.handle auth record edit)
        |> Task.map (\( refreshed, () ) -> rotatedBluesky account refreshed)
