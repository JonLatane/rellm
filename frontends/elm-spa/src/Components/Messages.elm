module Components.Messages exposing
    ( Conversation(..)
    , ConversationSummary
    , conversationHost
    , conversationKey
    , conversationMessages
    , eligibleServers
    , fetchFromEmail
    , fetchMessage
    , fetchMessageListing
    , fetchMessagingGroup
    , groupRouteId
    , hasEligibleAccount
    , isUnread
    , markMessagesRead
    , messageKey
    , messageMillis
    , parseGroupRouteId
    )

{-| Shared building blocks for `Components.Pages.MessagesPage` -- the
per-account fetch helpers (mirroring `Components.Users.fetchUserListing`) and
the client-side grouping of a flat `GetMessagesResponse.messages` list into
`MessagingGroup`s (there's no `GetMessagingGroups` RPC; only `GetMessages`,
which always returns messages -- see `protos/messages.proto`).

Unlike `Components.Users.fetchUserListing`'s unfiltered `EVERYONE` listing
(every _enabled_ server, no account needed), `GetMessages` always requires
auth (`backend/src/rpcs/messages/get_messages.rs`'s `validate_permission`
rejects an anonymous `user`), so `eligibleServers` scopes this to every
signed-in account that actually has the relevant permission, one
`MessageListingType` decision per account -- see its own doc.

-}

import Dict exposing (Dict)
import Grpc
import Proto.Rellm exposing (Author, GetMessagesRequest, GetMessagesResponse, Message, MessageRead, defaultGetMessagesRequest, defaultMarkMessagesReadRequest)
import Proto.Rellm.MessageListingType exposing (MessageListingType(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel exposing (performWithAccountServer)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (timestampToPosix)
import Task exposing (Task)
import Time


{-| One eligible `(Server, Account, MessageListingType)` triple to fetch
messages from -- one entry per signed-in account that has the relevant
permission (or `ADMIN`) on its own server, never more than one entry per
account. Prefers `PERSONALMESSAGES` (a user's own inbox) over
`ALLSYSTEMMESSAGES` (the whole server's firehose) whenever an account has
both -- an account signed in somewhere is far more likely to want their own
messages front and center than every message on the server; there's no UI
toggle between the two in v1.

Resolves `account.server` via `RellmServers.knownConnectedRellmServer`, not plain
`serverForHost` -- `GetMessages` is a real route-driven fetch (see
`MessagesPage.fetchNewServers`), and `knownConnectedServer`'s own doc comment
explains why: `serverForHost` alone would happily match the disconnected
placeholder `AccountsPanel.init` seeds every persisted server with before its
reconnect resolves, letting the very first fetch fire (and fail instantly,
client-side, no network call) against a server that isn't actually reachable
yet -- and since `fetchNewServers` only retries an entry when its
account/listingType changes, that failure would stick around unretried for
the rest of the page's lifetime, even once the real connection lands moments
later. Excluding a not-yet-connected account from `eligibleServers` entirely
instead means no fetch (and no `Failed` status) is ever recorded for it, so
the very next `Poll` (fired off the `Shared.AccountsPanelMsg` that connecting
itself dispatches -- see `Pages.Messages.update`) sees it as brand new and
fetches for the first time, successfully.

-}
eligibleServers : AccountsPanel.Model -> List { server : RellmServer, account : RellmAccount, listingType : MessageListingType }
eligibleServers accountsPanelModel =
    AccountsPanel.enabledAccounts accountsPanelModel
        |> List.filterMap
            (\account ->
                let
                    listingType : Maybe MessageListingType
                    listingType =
                        if RellmAccounts.isAdmin account || List.member READPERSONALMESSAGES account.permissions then
                            Just PERSONALMESSAGES

                        else if List.member READALLSYSTEMMESSAGES account.permissions then
                            Just ALLSYSTEMMESSAGES

                        else
                            Nothing
                in
                Maybe.map2 (\server lt -> { server = server, account = account, listingType = lt })
                    (RellmServers.knownConnectedRellmServer accountsPanelModel.servers account.server)
                    listingType
            )


{-| Whether `accountsPanelModel` has at least one `eligibleServers` entry --
gates both the Messages nav icon (`Shared.MessagingPanel.hasEligibleAccount`)
and the page's own "nothing to show" empty state. Mirrors
`Shared.CreateNewPanel.hasEligibleAccount`.
-}
hasEligibleAccount : AccountsPanel.Model -> Bool
hasEligibleAccount accountsPanelModel =
    not (List.isEmpty (eligibleServers accountsPanelModel))


{-| The `*_TEXT_SEARCH` counterpart of `listingType` -- mirrors
`Components.Users.textSearchListingType`.
-}
textSearchListingType : MessageListingType -> MessageListingType
textSearchListingType listingType =
    case listingType of
        PERSONALMESSAGES ->
            PERSONALMESSAGESTEXTSEARCH

        ALLSYSTEMMESSAGES ->
            ALLSYSTEMMESSAGESTEXTSEARCH

        other ->
            other


{-| Fetches `listingType`'s listing (or its `textSearchListingType`
counterpart, if `searchText` isn't blank) from `maybeAccountServer`'s server,
authenticated as its account -- mirrors `Components.Users.fetchUserListing`.
-}
fetchMessageListing :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MessageListingType
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMessagesResponse )
fetchMessageListing accountsPanelModel maybeAccountServer listingType searchText =
    let
        trimmedSearchText : String
        trimmedSearchText =
            String.trim searchText

        request : GetMessagesRequest
        request =
            if String.isEmpty trimmedSearchText then
                { defaultGetMessagesRequest | listingType = listingType }

            else
                { defaultGetMessagesRequest
                    | listingType = textSearchListingType listingType
                    , searchText = Just trimmedSearchText
                }
    in
    fetchMessages accountsPanelModel maybeAccountServer request


{-| Fetches every message in `groupId` (most-recent-first, per
`get_messaging_group_messages`) -- what expanding a `MessagingGroup`
conversation (or two-pane `selectedGroup`) in `Components.Pages.MessagesPage`
fetches. `listingType` should be the same `PERSONALMESSAGES`/`ALLSYSTEMMESSAGES`
(never the `*_TEXT_SEARCH` variant -- a group's own full thread isn't itself
filtered by the outer listing's search) the group was found under, from
`eligibleServers`.

Never called for a `SoloMessage` pseudo-group (see `conversationMessages`/`Conversation`)
-- there's only ever the one already-in-hand message for those, no group id
to fetch by; `fetchMessage` is that kind's own counterpart.

-}
fetchMessagingGroup :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MessageListingType
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMessagesResponse )
fetchMessagingGroup accountsPanelModel maybeAccountServer listingType groupId =
    fetchMessages accountsPanelModel maybeAccountServer { defaultGetMessagesRequest | listingType = listingType, messageGroupId = Just groupId }


{-| Fetches every message whose email "from" header exactly matches `fromEmail`
(most-recent-first) -- the `FromEmail`-kind counterpart to `fetchMessagingGroup`,
for a message with no visible `messagingGroup` (see `Conversation`'s own doc)
whose sender address is known. `fromEmail` should be some prior response's own
`Message.from`, verbatim -- matching is an exact string comparison server-side
(`GetMessagesRequest.from_email`'s own proto doc), not a normalized-address
comparison, and (per that same doc) `from` is unauthenticated/spoofable to
begin with.
-}
fetchFromEmail :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MessageListingType
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMessagesResponse )
fetchFromEmail accountsPanelModel maybeAccountServer listingType fromEmail =
    fetchMessages accountsPanelModel maybeAccountServer { defaultGetMessagesRequest | listingType = listingType, fromEmail = Just fromEmail }


{-| Fetches the single message `messageId` (assuming the caller has access to
it) -- the `SoloMessage`-kind counterpart to `fetchMessagingGroup`/`fetchFromEmail`.
Only ever actually needed for a cold `?message=` permalink that never went
through this session's own outer listing fetch -- otherwise the message is
already fully in hand (see `Components.Pages.MessagesPage.expand`'s own doc),
and no RPC is fired at all.
-}
fetchMessage :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MessageListingType
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMessagesResponse )
fetchMessage accountsPanelModel maybeAccountServer listingType messageId =
    fetchMessages accountsPanelModel maybeAccountServer { defaultGetMessagesRequest | listingType = listingType, messageId = Just messageId }


fetchMessages :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> GetMessagesRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMessagesResponse )
fetchMessages accountsPanelModel maybeAccountServer request =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getMessages request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| What a `ConversationSummary` (`Components.Pages.MessagesPage`) is actually
backed by, and so how it can be expanded into its full message list and what
query param identifies it in a permalink -- each variant's own payload _is_
that backing id (second `String`), plus the host it lives on (first `String`),
so a bare `Conversation` value is always a complete, self-contained identity
(see `conversationHost`/`conversationId`/`conversationKey` for pulling pieces
back out of it, e.g. to build a `"<host>|<id>"` Dict key or fetch by the raw
id alone):

  - `MessagingGroup host groupId` -- a real `MessagingGroup.id`, fetched via
    `fetchMessagingGroup` (`GetMessagesRequest.message_group_id`), routed as
    `?messaging_group=`.
  - `FromEmail host fromEmail` -- no real server-side group at all, just
    every message sharing the same (unauthenticated, spoofable -- see
    `GetMessagesRequest.from_email`'s own proto doc) `Message.from` value,
    fetched via `fetchFromEmail`, routed as `?from_email=`. Assigned to
    _every_ message whose `from` is known, regardless of whether it also has
    a real `messagingGroup` -- deliberately not mutually exclusive with
    `MessagingGroup` above: the backend's own `from_email` filter
    (`get_by_from_email`) likewise doesn't exclude group messages, so a
    message can legitimately belong to both its real group's conversation
    _and_ the "everything from this address" pseudo-conversation at once (see
    `conversationMessages`' own doc).
  - `SoloMessage host messageId` -- a single message with no visible
    `messagingGroup` _and_ no known sender address to fall back on (e.g. an
    unparseable inbound email `From:` header) -- keyed by its own message id,
    since there's nothing else to group it by. Fetched via `fetchMessage`,
    routed as `?message=`; the common case needs no fetch at all, see that
    function's own doc.

-}
type Conversation
    = MessagingGroup String String
    | FromEmail String String
    | SoloMessage String String


{-| The server `conversation` lives on, regardless of variant -- always the
first `String` of whichever variant, see `Conversation`'s own doc.
-}
conversationHost : Conversation -> String
conversationHost conversation =
    case conversation of
        MessagingGroup host _ ->
            host

        FromEmail host _ ->
            host

        SoloMessage host _ ->
            host


{-| The backing id `conversation` carries, regardless of variant -- always
the second `String` of whichever variant, see `Conversation`'s own doc. Used
for dispatching straight to `fetchMessagingGroup`/`fetchFromEmail`/
`fetchMessage`, or building the `?messaging_group=`/`?from_email=`/`?message=`
query param value, where only the id itself (not which variant it came from,
nor its host) matters.
-}
conversationId : Conversation -> String
conversationId conversation =
    case conversation of
        MessagingGroup _ groupId ->
            groupId

        FromEmail _ fromEmail ->
            fromEmail

        SoloMessage _ messageId ->
            messageId


{-| `"<host>|<id>"` -- globally unique across every fetched server (a raw
`MessagingGroup.id`/`Message.id`/email address alone isn't unique across
servers, same reasoning as `Components.Users.followStatusAndButtonKey`), and
so what every `Dict String _` keyed by conversation in
`Components.Pages.MessagesPage` actually uses as its key, computed from
`conversation` on demand rather than carried alongside it as its own stored
field.
-}
conversationKey : Conversation -> String
conversationKey conversation =
    conversationHost conversation ++ "|" ++ conversationId conversation


{-| `"<host>|<id>"` for `message`, on `host` -- the message-level analog of
`conversationKey`, and for exactly the same reason: `Message.id` (like
`Conversation`'s own backing id) is a plain per-server sequence, not a
globally-unique value, so two messages from two different hosts can
perfectly well share the same raw id. Anywhere a `Message`'s own id is used
as a `Dict` key, an equality check, or otherwise compared against another
message from a _different, not-yet-confirmed-same_ host needs this, not the
bare `.id` -- see `Components.Pages.MessagesPage`'s own `Model.sidebarAnimations`/
`.detailThreadAnimations`/`.highlightMessageId`/`.pendingScrollMessageId`
for what this guards against (a real bug this session: the sidebar's own
flattened message list, spanning every inline-open group across every host
at once, collided on exactly this).
-}
messageKey : String -> Message -> String
messageKey host message =
    host ++ "|" ++ message.id


{-| One `MessagingGroup` (or `FromEmail`/`SoloMessage` pseudo-group, see
`Conversation`) summarized down to its most recent message -- what
`Components.Pages.MessagesPage`'s outer list renders/sorts/animates.
`unreadCount` counts every fetched message in the group with `isUnread ==
True` -- not just whether `mostRecent` itself is unread -- so it stays
accurate once an older message's read status changes independently (e.g.
`MessagesPage` marking a whole thread read on expand doesn't necessarily touch
every message at once). `messageCount` counts every fetched message in the
group, full stop -- since the _outer_ listing this is built from
(`conversationMessages`, always called on a `GetMessagesRequest` with no
`messageGroupId`/`fromEmail`) is only ever the server's most recent
`PAGE_SIZE` messages _across every group_, not this group's full history,
this is a floor, not a total -- `MessagesPage.groupMessageCountView` is what
appends a "+" to make that clear, unless the group's own full thread has
separately been fetched (`expand`/`fetchExpand`, keyed by `conversationKey`),
in which case that fetch's own message count _is_ the true total.
-}
type alias ConversationSummary =
    { conversation : Conversation
    , members : List Author
    , mostRecent : Message
    , unreadCount : Int
    , messageCount : Int
    }


{-| Groups a flat, `created_at DESC`-sorted `messages` list (as
`GetMessagesResponse` always returns them) into every `Conversation` each
message belongs to -- there's no `GetMessagingGroups` RPC, only `GetMessages`,
so this is the only way to derive a group listing at all. A message with a
real `messagingGroup` counts toward that `MessagingGroup` conversation; a
message with a known `from` address _also_ (not "instead") counts toward the
`FromEmail` conversation for that address, per `FromEmail`'s own doc -- so a
message with both counts toward two different `ConversationSummary`s at once,
each with its own independent `mostRecent`/`unreadCount`/`messageCount`. Only
a message with neither (the client was Bcc'ed with no parseable `from`, or the
message otherwise has no visible group -- per `Message.messaging_group`'s own
proto doc) falls back to `SoloMessage`, its own pseudo-group of exactly one.
See `Conversation`'s own doc. Result is sorted by each group's `mostRecent`
message, most-recent-first.
-}
conversationMessages : String -> List Message -> List ConversationSummary
conversationMessages host messages =
    let
        applicableConversations : Message -> List ( Conversation, List Author )
        applicableConversations message =
            let
                soloMembers : List Author
                soloMembers =
                    message.sender |> Maybe.map List.singleton |> Maybe.withDefault []

                groupEntry : Maybe ( Conversation, List Author )
                groupEntry =
                    message.messagingGroup |> Maybe.map (\group -> ( MessagingGroup host group.id, group.members ))

                fromEmailEntry : Maybe ( Conversation, List Author )
                fromEmailEntry =
                    message.from |> Maybe.map (\fromEmail -> ( FromEmail host fromEmail, soloMembers ))
            in
            case ( groupEntry, fromEmailEntry ) of
                ( Nothing, Nothing ) ->
                    [ ( SoloMessage host message.id, soloMembers ) ]

                _ ->
                    List.filterMap identity [ groupEntry, fromEmailEntry ]

        addToConversation : Message -> ( Conversation, List Author ) -> Dict String ConversationSummary -> Dict String ConversationSummary
        addToConversation message ( conversation, members ) groups =
            let
                key : String
                key =
                    conversationKey conversation

                increment : Int
                increment =
                    if isUnread message then
                        1

                    else
                        0
            in
            case Dict.get key groups of
                Nothing ->
                    Dict.insert key
                        { conversation = conversation, members = members, mostRecent = message, unreadCount = increment, messageCount = 1 }
                        groups

                Just existing ->
                    Dict.insert key
                        { existing
                            | mostRecent =
                                if messageMillis message > messageMillis existing.mostRecent then
                                    message

                                else
                                    existing.mostRecent
                            , unreadCount = existing.unreadCount + increment
                            , messageCount = existing.messageCount + 1
                        }
                        groups

        addMessage : Message -> Dict String ConversationSummary -> Dict String ConversationSummary
        addMessage message groups =
            List.foldl (addToConversation message) groups (applicableConversations message)
    in
    List.foldl addMessage Dict.empty messages
        |> Dict.values
        |> List.sortBy (\group -> -(messageMillis group.mostRecent))


{-| `True` iff `message.currentUserRead` hasn't been set -- see that field's
own proto doc comment. Used both to compute `ConversationSummary.unreadCount` and by
`MessagesPage` to decide which messages to `markMessageRead` once their
thread's actually been viewed.
-}
isUnread : Message -> Bool
isUnread message =
    message.currentUserRead == Nothing


{-| Marks every id in `messageIds` read or unread (`MarkMessagesReadRequest.unread`),
all in one request, as `maybeAccountServer`'s account. Two callers:
`MessagesPage` fires this with `unread = False` once per thread, for every
`isUnread` message in it at once, right when that thread's finished loading
(see its own `GotGroupMessages` handling); its own "Mark unread" button
(`MarkUnreadClicked`) fires it with `unread = True` for a single already-read
message instead. `messageIds` empty is a caller bug (the RPC itself rejects
it) -- both callers only ever call this with a non-empty list.
-}
markMessagesRead :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Bool
    -> List String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, List MessageRead )
markMessagesRead accountsPanelModel maybeAccountServer unread messageIds =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.markMessagesRead { defaultMarkMessagesReadRequest | messageIds = messageIds, unread = unread }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )
        |> Task.map (Tuple.mapSecond .messageReads)


{-| `message.createdAt`, in epoch milliseconds -- what `conversationMessages` sorts
by, and what `Components.Pages.MessagesPage` sorts an expanded group's own
messages by too. `0` (the epoch -- always sorts last) for the
never-actually-happens case of a missing `createdAt`, same fallback
convention as this codebase's other optional-timestamp sorts.
-}
messageMillis : Message -> Int
messageMillis message =
    message.createdAt
        |> Maybe.map (timestampToPosix >> Time.posixToMillis)
        |> Maybe.withDefault 0


{-| The inverse of `groupRouteId`: `raw` is either a bare id (on
`mainFrontendHost`) or `id@host` (on some other, federated-in-account server)
-- mirrors `Components.Users.parseUserRouteId`/`Components.Posts.parsePostRouteId`.
Used for both `?messaging_group=` (a `MessagingGroup.id`) and `?message=` (a
`Message.id`) -- both are opaque server-assigned ids that never themselves
contain `@`, so the same bare-id-or-`id@host` shape and split logic works for
either. _Not_ used for `?from_email=`: an email address already contains its
own `@`, so `MessagesPage.groupQueryParams`/`Pages.Messages.init` route that
kind through a separate `from_email_host` param instead of this suffix.
-}
parseGroupRouteId : String -> String -> ( String, String )
parseGroupRouteId mainFrontendHost raw =
    case String.split "@" raw of
        [ id, host ] ->
            ( id, host )

        _ ->
            ( raw, mainFrontendHost )


{-| The `?messaging_group=`/`?message=` value for an id on `groupHost` --
mirrors `Components.Users`' own (private) `withHostSuffix`. See `parseGroupRouteId`'s
own doc on why this same helper covers both query params.
-}
groupRouteId : String -> String -> String -> String
groupRouteId mainFrontendHost groupHost groupId =
    if groupHost == mainFrontendHost then
        groupId

    else
        groupId ++ "@" ++ groupHost
