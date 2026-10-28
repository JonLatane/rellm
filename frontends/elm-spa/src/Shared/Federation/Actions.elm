module Shared.Federation.Actions exposing
    ( ServerAccount(..)
    , accountId
    , avatarUrlOf
    , createPost
    , hostOf
    , postWebUrl
    , usableAccounts
    , deletePost
    , editPost
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
            "Not allowed. If this is a Mastodon account connected before posting was supported, disconnect and reconnect it to grant permission."

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
