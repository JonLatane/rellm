module Components.SyncDestinations exposing
    ( createSyncDestination
    , deleteSyncDestination
    , getSyncDestinations
    , syncDestinationsView
    )

{-| RPC wrappers for `SyncDestination` (`protos/sync.proto`) -- mirrors
`Components.SyncSources` in shape (each takes the calling account/server as an
`AccountsPanel.MaybeAccountServer` and returns a `Task` resolving to `( Maybe AccountsPanel.Msg,
response )`). There's no `updateSyncDestination` wrapper here -- reconnecting an existing
destination isn't exposed in the UI yet, only link/unlink.

`Components.Pages.UserProfilePage`'s own "Sync Destinations" section never calls `getSyncDestinations`
-- it already has the account's full `User` (via `Components.Users.Resolver`), which embeds
`syncDestinations` directly (self-or-Admin gated server-side, see `protos/users.proto`'s doc on
`User.sync_destinations`). `getSyncDestinations` exists for pages that only need _just_ that list
without fetching a whole `User` -- e.g. `Pages.Event.PostId_`/`Components.Pages.PostPage`, which
need the viewer's own destinations to offer a real Push button on a single Post/Occasion's
detail view, but have no other reason to fetch their own full profile.

Also home to `syncDestinationsView`, the generic already-synced/available-to-sync-to row-rendering
logic shared by `Components.Events.eventSyncDestinationsView` (wrapping
`Occasion.syncDestinations`) and `Components.Posts.postSyncDestinationsView` (wrapping
`Post.syncDestinations`) -- see that function's own doc for the union/rendering rules.

-}

import Grpc
import Html exposing (Html, a, b, button, div, span, text)
import Html.Attributes exposing (class, disabled, href, rel, target, title)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (GetSyncDestinationsResponse, SyncDestination, SyncDestinationStatus, defaultUser)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.SyncDestination.Configuration as DestinationConfiguration
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Task exposing (Task)


{-| `targetUserId = ""` asks the backend for the caller's own destinations (see
`backend/src/rpcs/sync_destinations/get_sync_destinations.rs`); any other id asks for that user's
destinations instead, which only succeeds for an Admin caller. Mirrors
`Components.SyncSources.getSyncSources`'s own doc/shape exactly.
-}
getSyncDestinations :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetSyncDestinationsResponse )
getSyncDestinations accountsPanelModel maybeAccountServer targetUserId =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getSyncDestinations { defaultUser | id = targetUserId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Always creates a destination owned by the calling account (mirrors
`createSyncSource`'s own doc -- the backend ignores/overrides any `owner` sent). Requires
`SYNC_EVENTS_TO_FACEBOOK` or `SYNC_POSTS_TO_FACEBOOK` (or Admin) server-side.
-}
createSyncDestination :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> SyncDestination
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination )
createSyncDestination accountsPanelModel maybeAccountServer destination =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.createSyncDestination destination
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| `deleteSyncedPosts` is always sent `False` here -- there's no UI for the "also delete the
Facebook posts" option yet (see `DeleteSyncDestinationRequest.deleteSyncedPosts`), only a
plain unlink.
-}
deleteSyncDestination :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> SyncDestination
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteSyncDestination accountsPanelModel maybeAccountServer destination =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteSyncDestination
                { destination = Just destination, deleteSyncedPosts = False }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| `Nothing` renders one line per `syncDestinations` entry with a
`destinationUrl` set, linking out to wherever the content item was synced to (e.g. the resulting
Facebook post) -- read-only, no push controls -- used by every caller except
`Components.Pages.UserProfilePage`'s embedded feeds.

`Just availableDestinations` renders a unified row list instead: one row per destination id in
`syncDestinations` (already synced, shows its URL if any) unioned with any of
`availableDestinations` not yet in that list (not yet synced, no URL), each with a "Push"/"Push
again" button -- `isPushing`/`pushError` (keyed by destination id) drive its disabled/error state,
`onPush` fires the push. Already-synced rows also get a Delete button (`onDelete`, given the
destination id and its display name for the confirmation dialog -- see
`Shared.ConfirmOccasionSyncDestinationDelete`/`Shared.ConfirmPostSyncDestinationDelete`),
which removes just the local sync record, putting the row back into its unsynced "Push" state.
This `Maybe` is the _only_ gate on whether push/delete controls show at all -- deciding when to
pass `Just` (only `UserProfilePage`'s own embedded feeds, for now) is entirely the caller's call;
this module has no opinion on `AccountsPanel`/permissions.

Shared by `Components.Events.eventSyncDestinationsView` (passing `occasion.syncDestinations`) and
`Components.Posts.postSyncDestinationsView` (passing `post.syncDestinations`) -- both thin
wrappers over this. Rendered with the platform-agnostic `.card-sync-destinations`/
`.card-sync-destination-*`/`.synced-to*` classes `events.css` defines for this row layout, rather
than a separate `.post-*` set -- they're purely visual and carry no event- or post-specific
selector, so they render identically for a Post card/detail view.

`hasMedia` is whether the Post/Occasion being synced has any attached media -- Instagram's
Graph API has no text-only post type, so a row whose destination is an `InstagramAccount` gets its
Push button disabled (with an explanatory label) when this is `False`, rather than letting the
click round-trip to a guaranteed `instagram_requires_media` server error. Irrelevant to every other
platform.

-}
syncDestinationsView :
    List SyncDestinationStatus
    -> Maybe (List SyncDestination)
    -> Bool
    -> (String -> Bool)
    -> (String -> Maybe String)
    -> (String -> msg)
    -> (String -> String -> msg)
    -> Html msg
syncDestinationsView syncDestinations availableSyncDestinations hasMedia isPushing pushError onPush onDelete =
    case availableSyncDestinations of
        Nothing ->
            let
                urls : List String
                urls =
                    syncDestinations |> List.filterMap .destinationUrl
            in
            if List.isEmpty urls then
                text ""

            else
                div [ class "synced-to" ]
                    (urls
                        |> List.map
                            (\url ->
                                div [ class "synced-to-line" ]
                                    [ text "synced to "
                                    , a [ href url, target "_blank", rel "noopener noreferrer", class "synced-to-link" ] [ text url ]
                                    ]
                            )
                    )

        Just availableDestinations ->
            let
                lookupDestination : String -> Maybe SyncDestination
                lookupDestination id =
                    availableDestinations
                        |> List.filter (\d -> d.id == id)
                        |> List.head

                destinationName : String -> Maybe String
                destinationName id =
                    lookupDestination id
                        |> Maybe.andThen .configuration
                        |> Maybe.map
                            (\config ->
                                case config of
                                    DestinationConfiguration.FacebookPage page ->
                                        page.pageName

                                    DestinationConfiguration.InstagramAccount account ->
                                        "@" ++ account.username

                                    DestinationConfiguration.MastodonAccount account ->
                                        account.username ++ "@" ++ account.instanceHost

                                    DestinationConfiguration.BlueskyAccount account ->
                                        account.handle

                                    DestinationConfiguration.XTwitterAccount account ->
                                        "@" ++ account.username

                                    DestinationConfiguration.ThreadsAccount account ->
                                        "@" ++ account.username
                            )

                -- Shown in parentheses after `destinationName` (e.g. "My Profile (Facebook)") so
                -- a destination's platform is legible without decoding its handle/page name.
                platformLabel : String -> Maybe String
                platformLabel id =
                    lookupDestination id
                        |> Maybe.andThen .configuration
                        |> Maybe.map
                            (\config ->
                                case config of
                                    DestinationConfiguration.FacebookPage _ ->
                                        "Facebook"

                                    DestinationConfiguration.InstagramAccount _ ->
                                        "Instagram"

                                    DestinationConfiguration.MastodonAccount _ ->
                                        "Mastodon"

                                    DestinationConfiguration.BlueskyAccount _ ->
                                        "Bluesky"

                                    DestinationConfiguration.XTwitterAccount _ ->
                                        "X (Twitter)"

                                    DestinationConfiguration.ThreadsAccount _ ->
                                        "Threads"
                            )

                -- Instagram's Graph API has no text-only post type -- see `hasMedia`'s own doc.
                isInstagramDestination : String -> Bool
                isInstagramDestination id =
                    case lookupDestination id |> Maybe.andThen .configuration of
                        Just (DestinationConfiguration.InstagramAccount _) ->
                            True

                        _ ->
                            False

                syncedRows : List { id : String, url : Maybe String, synced : Bool }
                syncedRows =
                    syncDestinations
                        |> List.map (\sd -> { id = sd.syncDestinationId, url = sd.destinationUrl, synced = True })

                syncedIds : List String
                syncedIds =
                    syncedRows |> List.map .id

                notYetSyncedRows : List { id : String, url : Maybe String, synced : Bool }
                notYetSyncedRows =
                    availableDestinations
                        |> List.filter (\d -> not (List.member d.id syncedIds))
                        |> List.map (\d -> { id = d.id, url = Nothing, synced = False })

                rows : List { id : String, url : Maybe String, synced : Bool }
                rows =
                    syncedRows ++ notYetSyncedRows
            in
            if List.isEmpty rows then
                text ""

            else
                div [ class "card-sync-destinations" ]
                    (rows |> List.map (syncDestinationRowView destinationName platformLabel isInstagramDestination hasMedia isPushing pushError onPush onDelete))


syncDestinationRowView :
    (String -> Maybe String)
    -> (String -> Maybe String)
    -> (String -> Bool)
    -> Bool
    -> (String -> Bool)
    -> (String -> Maybe String)
    -> (String -> msg)
    -> (String -> String -> msg)
    -> { id : String, url : Maybe String, synced : Bool }
    -> Html msg
syncDestinationRowView destinationName platformLabel isInstagramDestination hasMedia isPushing pushError onPush onDelete row =
    let
        pushing : Bool
        pushing =
            isPushing row.id

        -- See `syncDestinationsView`'s own doc on `hasMedia` -- Instagram can't post without an
        -- attached image/video, so this row's Push button is disabled rather than letting the
        -- click round-trip to a guaranteed `instagram_requires_media` server error.
        instagramNeedsMedia : Bool
        instagramNeedsMedia =
            isInstagramDestination row.id && not hasMedia

        label : String
        label =
            if pushing then
                "Pushing…"

            else if instagramNeedsMedia then
                "Instagram requires an image"

            else if row.url == Nothing then
                "Push"

            else
                "Push again"

        name : String
        name =
            destinationName row.id |> Maybe.withDefault "Facebook Page"
    in
    div [ class "card-sync-destination-row" ]
        [ span [ class "card-sync-destination-name" ]
            [ b [] [ text name ]
            , case platformLabel row.id of
                Just platform ->
                    span [ class "card-sync-destination-platform" ] [ text (" (" ++ platform ++ ")") ]

                Nothing ->
                    text ""
            ]
        , case row.url of
            Just url ->
                a
                    [ href url
                    , target "_blank"
                    , rel "noopener noreferrer"
                    , class "card-sync-destination-link"
                    ]
                    [ text url ]

            Nothing ->
                text ""
        , button
            [ class "card-sync-destination-push"
            , onClick (onPush row.id)
            , disabled (pushing || instagramNeedsMedia)
            , title
                (if instagramNeedsMedia then
                    "Instagram requires an image"

                 else
                    ""
                )
            ]
            [ text label ]
        , if row.synced then
            button
                [ class "card-sync-destination-delete"
                , onClick (onDelete row.id name)
                , disabled pushing
                ]
                [ text "Delete" ]

          else
            text ""
        , case pushError row.id of
            Just err ->
                div [ class "card-sync-destination-push-error" ] [ text err ]

            Nothing ->
                text ""
        ]
