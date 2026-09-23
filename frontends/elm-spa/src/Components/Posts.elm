module Components.Posts exposing
    ( ContentCollapse
    , FederatedPostId(..)
    , allModerations
    , allowedVisibilities
    , commentCountText
    , contentPreviewFadeThreshold
    , deletePost
    , deletePostSyncDestination
    , fetchAncestors
    , fetchPost
    , fetchPosts
    , fetchReplies
    , generateMediaButton
    , isAuthor
    , mediaEditButton
    , mediaServer
    , moderationFromText
    , parseFederatedPostId
    , parsePostRouteId
    , postCard
    , postContextLabel
    , postDetail
    , postDetailContentDomId
    , postDetailContentPreviewHeight
    , postHref
    , postLinkText
    , postMediaLayoutFromText
    , postTimestamp
    , postTitleText
    , postVisibilityText
    , replyCard
    , showPostVisibility
    , starButton
    , stripLinkScheme
    , syncPost
    , updatePost
    , visibilityFromText
    , visibilityText
    )

{-| Shared building blocks for displaying `Proto.Rellm.Post`s -- the compact
`postCard` used in the Home page's recent-posts feed, the fuller `postDetail`
used by the Post page, and the fetch/link helpers both (and any future
Post-related page) need: building a `GetPosts` request against a specific
`Shared.RellmServer` (optionally authenticated, via
`Shared.MaybeAccountRequest`), and building/parsing the `/post/:postId`
route's `id` or `id@host` segment.
-}

import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.SyncDestinations as SyncDestinations
import Components.Users as Users
import Gen.Route
import Grpc
import Html exposing (Html, a, button, div, h1, option, select, span, text)
import Html.Attributes exposing (attribute, class, href, id, rel, selected, style, target, title, value)
import Html.Events
import Proto.Rellm exposing (GetPostsResponse, Post, SyncDestination, defaultGetPostsRequest, defaultPost)
import Proto.Rellm.Moderation exposing (Moderation(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.PostListingType exposing (PostListingType(..))
import Proto.Rellm.PostMediaLayout exposing (PostMediaLayout(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.AccountsPanel as AccountsPanel exposing (performWithAccountServer, performWithOptionalAccountServer)
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (int64ToInt, posixToTimestamp, timestampToPosix)
import Shared.Federation.Common exposing (sensitiveMediaHiddenId)
import Shared.Time as SharedTime
import Task exposing (Task)
import Time
import UI.Classes exposing (classes, hostnameToCSSClass)
import UI.HtmlEvents exposing (stopPropagationAndPreventDefaultOnClick)


{-| Fetches a single post (including reply/preview data) from
`maybeAccountServer`'s server, authenticated as its account if any, anonymous
otherwise. Returns a `Msg` to dispatch (via whatever out-msg/`Effect`
mechanism the caller already uses) if a token refresh happened, so the
caller never has to know an `Account`/`AccessTokenResponse` was even
involved -- see `Shared.AccountsPanel.performWithOptionalAccountServer`.
-}
fetchPost :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse )
fetchPost accountsPanelModel maybeAccountServer postId =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getPosts { defaultGetPostsRequest | postId = Just postId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Fetches posts from `maybeAccountServer`'s server, authenticated as its
account if any (so e.g. followed-user/group posts are included too) --
otherwise identical to `fetchPost`. `authorUserId`, if given, restricts the
results to that user's posts (see `GetPostsRequest`'s `{listing_type:
AuthorPosts, author_user_id:}` form), for `Components.Pages.PostsPage`'s use
on a user's own posts page.

`searchText`, if non-blank (leading/trailing whitespace is trimmed, and a
blank string is treated the same as empty), switches the request to
`TEXT_SEARCH` -- otherwise this is the same "most recent publicly-accessible
posts" request `fetchRecentPosts` used to be. `context` is sent either way
(`GetPosts`' `TEXT_SEARCH` and default `ALL_ACCESSIBLE_POSTS` branches both
read it -- see `backend/src/rpcs/posts/get_posts.rs`), so
`Components.Pages.PostsPage`'s POST/REPLY chooser works whether or not
there's search text entered.

`publishedOrCreatedBefore`, if given, is sent as `GetPostsRequest`'s own
field of the same name -- `Components.Pages.PostsPage`'s "Posts Before
<date>" tab's cutoff (see that module's `PostsBeforeDate` tab), restricting
results to posts published (or, absent that, created) before it. `Nothing`
for the default "Recent Posts" tab, same as every other unset-filter
convention here.

-}
fetchPosts :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Maybe String
    -> String
    -> PostContext
    -> Maybe Time.Posix
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse )
fetchPosts accountsPanelModel maybeAccountServer authorUserId searchText context publishedOrCreatedBefore =
    let
        trimmedSearchText : String
        trimmedSearchText =
            String.trim searchText

        baseRequest : Proto.Rellm.GetPostsRequest
        baseRequest =
            if String.isEmpty trimmedSearchText then
                { defaultGetPostsRequest | authorUserId = authorUserId, context = Just context }

            else
                { defaultGetPostsRequest
                    | authorUserId = authorUserId
                    , listingType = TEXTSEARCH
                    , searchText = Just trimmedSearchText
                    , context = Just context
                }

        request : Proto.Rellm.GetPostsRequest
        request =
            { baseRequest
                | publishedOrCreatedBefore = Maybe.map posixToTimestamp publishedOrCreatedBefore
            }
    in
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getPosts request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Fetches the replies to `postId` from `maybeAccountServer`'s server,
`replyDepth` levels deep -- see `GetPostsRequest`'s doc comment: with
`post_id` and `reply_depth` both set, `GetPosts` returns the replies
themselves, not `postId`'s own Post), authenticated as its account if any,
anonymous otherwise -- same auth/refresh handling as `fetchPost`.
-}
fetchReplies :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Int
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse )
fetchReplies accountsPanelModel maybeAccountServer replyDepth postId =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getPosts { defaultGetPostsRequest | postId = Just postId, replyDepth = Just replyDepth }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Walks `post`'s own `replyToPostId` chain all the way up to (and including)
its root ancestor -- `Post` only carries its _children_ (`replies`), not its
parent, so there's no way to get this in one request. Returned root-first,
_not_ including `post` itself (the caller already has that) -- e.g. for a
reply-to-a-reply, `[root, parent]`. Empty if `post` has no `replyToPostId` at
all (it's already the root).

Used by `Pages.Post.PostId_` to populate `Shared.Breadcrumbs` for a Post
reached via a reply chain rather than directly. The whole walk (however many
hops it takes) happens inside a single `performWithOptionalAccountServer`
call -- see `fetchAncestorsHelp` -- so only one token-refresh check happens
for the whole chain, not one per hop.

-}
fetchAncestors :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Post
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, List Post )
fetchAncestors accountsPanelModel maybeAccountServer post =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken -> fetchAncestorsHelp server maybeToken post)


fetchAncestorsHelp : RellmServer -> Maybe String -> Post -> Task Grpc.Error (List Post)
fetchAncestorsHelp server maybeToken post =
    case post.replyToPostId of
        Nothing ->
            Task.succeed []

        Just parentId ->
            Grpc.new Rellm.getPosts { defaultGetPostsRequest | postId = Just parentId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
                |> Task.andThen
                    (\response ->
                        case List.head response.posts of
                            Just parentPost ->
                                fetchAncestorsHelp server maybeToken parentPost
                                    |> Task.map (\ancestors -> ancestors ++ [ parentPost ])

                            Nothing ->
                                Task.succeed []
                    )


{-| Re-fetches `postId` fresh (via `GetPosts`) before submitting `UpdatePost`
with `updateFn` applied to that fresh copy -- so a stale in-hand `Post` (e.g.
one rendered a while ago) can't clobber any field that changed server-side
since, other than the one(s) `updateFn` itself means to change. Mirrors
`Components.Users.updateUser` exactly (same re-fetch-then-overlay dance,
`GetPosts`/`UpdatePost` in place of `GetUsers`/`UpdateUser`) -- used by
`Pages.Post.PostId_`'s visibility editor.
-}
updatePost :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> (Post -> Post)
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Post )
updatePost accountsPanelModel maybeAccountServer postId updateFn =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getPosts { defaultGetPostsRequest | postId = Just postId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.andThen
                    (\response ->
                        case List.head response.posts of
                            Just freshPost ->
                                Grpc.new Rellm.updatePost (updateFn freshPost)
                                    |> Grpc.setHost (RellmServers.rellmServerUrl server)
                                    |> withAccessToken (Just token)
                                    |> Grpc.toTask

                            Nothing ->
                                Task.fail Grpc.NetworkError
                    )
        )


{-| Deletes `postId` outright (`DeletePost`, owner-or-Admin gated
server-side, see `backend/src/rpcs/posts/delete_post.rs`) -- unlike
`updatePost`, there's nothing to overlay onto a fresh copy first, so this
just sends the id straight through. Used by `Pages.Post.PostId_`'s own
Delete button, via `Shared.ConfirmPostDelete`.
-}
deletePost :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Post )
deletePost accountsPanelModel maybeAccountServer postId =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deletePost { defaultPost | id = postId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Pushes (cross-posts) `postId` to `syncDestinationId` (`SyncPost`,
owner-or-Admin gated server-side, see `backend/src/rpcs/posts/sync_post.rs`) -- mirrors
`Components.Events.syncOccasion`'s shape exactly. The returned `Post` carries a freshly
updated `syncDestinations`, but callers here just reuse their own existing full refetch rather
than patching it in by hand.
-}
syncPost :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Post )
syncPost accountsPanelModel maybeAccountServer postId syncDestinationId =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.syncPost
                { postId = postId, syncDestinationId = syncDestinationId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Removes `postId`'s sync (cross-post) to `syncDestinationId` (`DeletePostSyncDestination`,
owner-or-Admin gated server-side, see
`backend/src/rpcs/posts/delete_post_sync_destination.rs`) -- the reverse of `syncPost`, same
shape. Doesn't delete the post already made on the destination (e.g. the Facebook Page post),
only the local sync record, so the row goes back to its unsynced "Push" state (see
`Components.SyncDestinations.syncDestinationsView`'s `notYetSyncedRows`). Used by that view's
Delete button, via `Shared.ConfirmPostSyncDestinationDelete`.
-}
deletePostSyncDestination :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deletePostSyncDestination accountsPanelModel maybeAccountServer postId syncDestinationId =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deletePostSyncDestination
                { postId = postId, syncDestinationId = syncDestinationId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| Thin wrapper over `Components.SyncDestinations.syncDestinationsView`, extracting
`post.syncDestinations` (and `not (List.isEmpty post.media)` for that view's `hasMedia`, which
gates Instagram rows' Push button) -- see that function's own doc for the full already-synced/
available-to-sync-to union and rendering rules; only `Components.Pages.UserProfilePage`'s
embedded posts feed ever passes `Just` for `availableSyncDestinations`, giving every other caller
a read-only, no-push-controls rendering.
-}
postSyncDestinationsView :
    Maybe (List SyncDestination)
    -> (String -> Bool)
    -> (String -> Maybe String)
    -> (String -> msg)
    -> (String -> String -> msg)
    -> Post
    -> Html msg
postSyncDestinationsView availableSyncDestinations isPushing pushError onPush onDelete post =
    SyncDestinations.syncDestinationsView post.syncDestinations availableSyncDestinations (not (List.isEmpty post.media)) isPushing pushError onPush onDelete


{-| The "★ N" star button of a post's meta line -- clickable (unless
`onStarClicked` is `Nothing`, e.g. its server isn't resolvable) to star/unstar
the post (see `Shared.StarredPanel`), filling with `postServerHost`'s
`primaryAnchorColor` (`.post-star.starred`, see `UI.EmittedStylesheet`) and
animating the fill via `transition` in `posts.css` when `starred` flips.
`stopPropagation`/`preventDefault` keep a click here from also following
`postCard`'s enclosing link.
-}
starButton : String -> Bool -> Maybe msg -> Post -> Html msg
starButton postServerHost starred onStarClicked post =
    span
        (classes
            (hostnameToCSSClass postServerHost
                :: "post-star"
                :: (if starred then
                        [ "starred" ]

                    else
                        []
                   )
            )
            :: (case onStarClicked of
                    Just msg ->
                        [ stopPropagationAndPreventDefaultOnClick msg ]

                    Nothing ->
                        []
               )
        )
        [ text ("★ " ++ String.fromInt (postStarCount post)) ]


{-| A single `Post` timestamp, formatted the same way
`Components.Events.occasionWhenText` formats an `Occasion` moment (e.g.
"August 1, 6PM", or "Today, August 1, 6PM" -- see `SharedTime.formatMoment`/
`dateLabel`) rather than a range, since a bare timestamp (created/updated/
published) is always a single point in time. `timestampsText`'s own sibling
-- used for its created/updated/published times, so a post's timestamps read
the same as an event's own "when" line.
-}
whenText : SharedTime.Model -> Time.Posix -> String
whenText time moment =
    SharedTime.formatMoment time moment


{-| A post's created/updated/published times, as tersely as the data allows --
just one of the three normally (whichever's most relevant: `Published` if the
post has been published, else `Created`, else, in the one case a post could
have only this, `Updated`), with a trailing `*` plus a tooltip (native `title`)
covering the other one(s) whenever there's a genuinely _different_ edit
time to call out. Redundant fields (e.g. `publishedAt` equal to `createdAt`,
the common case for a post that was published immediately) are dropped
entirely rather than stated twice. All times shown in `time.browserTimeZone`
via `whenText` (e.g. "August 1, 6PM"), `time.now` supplying its own "current
year"/"current day".
-}
timestampsText : SharedTime.Model -> Post -> Html msg
timestampsText time post =
    let
        createdText : Maybe String
        createdText =
            Maybe.map (timestampToPosix >> whenText time) post.createdAt

        updatedText : Maybe String
        updatedText =
            Maybe.map (timestampToPosix >> whenText time) post.updatedAt

        publishedText : Maybe String
        publishedText =
            Maybe.map (timestampToPosix >> whenText time) post.publishedAt

        createdEqualsPublished : Bool
        createdEqualsPublished =
            createdText /= Nothing && createdText == publishedText

        ( mainText, titleText ) =
            case ( createdText, updatedText, publishedText ) of
                ( Just created, Just updated, Just published ) ->
                    if createdEqualsPublished then
                        if updated == created then
                            ( "Created " ++ created, "" )

                        else
                            ( "Created " ++ created ++ "*", "Updated " ++ updated )

                    else if updated == published then
                        ( "Published " ++ published, "Created " ++ created )

                    else
                        ( "Published " ++ published ++ "*", "Updated " ++ updated ++ ", Created " ++ created )

                ( Just created, Just updated, Nothing ) ->
                    if updated == created then
                        ( "Created " ++ created, "" )

                    else
                        ( "Created " ++ created ++ "*", "Updated " ++ updated )

                ( Just created, Nothing, Just published ) ->
                    if createdEqualsPublished then
                        ( "Created " ++ created, "" )

                    else
                        ( "Published " ++ published, "Created " ++ created )

                ( Just created, Nothing, Nothing ) ->
                    ( "Created " ++ created, "" )

                ( Nothing, Just updated, Just published ) ->
                    if updated == published then
                        ( "Published " ++ published, "" )

                    else
                        ( "Published " ++ published ++ "*", "Updated " ++ updated )

                ( Nothing, Just updated, Nothing ) ->
                    ( "Updated " ++ updated, "" )

                ( Nothing, Nothing, Just published ) ->
                    ( "Published " ++ published, "" )

                ( Nothing, Nothing, Nothing ) ->
                    ( "", "" )
    in
    span
        [ class "post-timestamps"
        , title titleText
        ]
        [ text mainText ]


{-| An Edit button below `postDetail`'s Markdown content, shown only to
`post`'s own author (see `isAuthor`) -- `maybeAccount` is `postDetail`'s own
(the enabled account for the post's server, same one used for
`postAuthorAvatarUrl`), not necessarily `post.author` itself. Opens the shared
Markdown editor panel via `onEditClicked`, supplied by the caller
(`Pages.Post.PostId_`).

Hidden entirely for a Post synced in from an RSS/Atom `SyncSource` (`post.syncSource /= Nothing`
-- see `posts.proto`'s `Post.sync_source`), mirroring `Components.Events.hasIcsSyncSource`/
`Components.Pages.EventPage.editable`'s same lock for a synced `Event`: such a Post's `content`
gets silently overwritten back to the feed's own text on every subsequent sync run (see
`logic::sync_sources::feed_sync::sync_post_text`), so a local edit here would just be clobbered.
`postDetail` renders `title`/`link` as plain, non-editable text regardless of `syncSource` --
there's no separate edit affordance for either to lock in the first place, only `content` goes
through this button.

-}
editContentButton : Maybe RellmAccount -> msg -> Post -> Html msg
editContentButton maybeAccount onEditClicked post =
    case maybeAccount of
        Just account ->
            if isAuthor account post && post.syncSource == Nothing then
                button [ class "post-edit-button", Html.Events.onClick onEditClicked ] [ text "Edit Content" ]

            else
                text ""

        Nothing ->
            text ""


{-| `editButton`'s counterpart for `postDetail`'s media block -- shown below
`MultiMediaRenderer.view` (see `postDetail`) to `post`'s own author (same
`isAuthor` gate as `editButton`) _or_ an `ADMIN` account, mirroring
`backend/src/rpcs/posts/update_post.rs`'s own `admin || self_update` check
(that's what actually gates whether an `UpdatePost` carrying a changed
`media` list is accepted at all). Opens the shared `Shared.MyMediaPanel`
media chooser via `onMediaEditClicked` (`Pages.Post.PostId_`'s own
`MediaEditClicked`), unlike `editButton`'s Markdown panel.
-}
mediaEditButton : Maybe RellmAccount -> msg -> Post -> Html msg
mediaEditButton maybeAccount onMediaEditClicked post =
    case maybeAccount of
        Just account ->
            if isAuthor account post || List.member ADMIN account.permissions then
                button [ class "post-media-edit-button", Html.Events.onClick onMediaEditClicked ] [ text "Edit Media" ]

            else
                text ""

        Nothing ->
            text ""


{-| `mediaEditButton`'s sibling, opening `Shared.MediaGeneratorPanel` instead of `Shared.MyMediaPanel`
-- same `isAuthor`-or-`ADMIN` gate, but `onGenerateMediaClicked` is itself a `Maybe msg` (not a bare
`msg`, unlike every other button here) since the caller also has to know whether the viewer has any
image-capable `AIModel` at all (`Account.aiModels`) before this button makes sense
to offer -- `Nothing` there covers both "not this post's author/an Admin" and "no model available",
without `Components.Posts` itself needing to know anything about `AIModel`.
-}
generateMediaButton : Maybe RellmAccount -> Maybe msg -> Post -> Html msg
generateMediaButton maybeAccount onGenerateMediaClicked post =
    case ( maybeAccount, onGenerateMediaClicked ) of
        ( Just account, Just onClicked ) ->
            if isAuthor account post || List.member ADMIN account.permissions then
                button [ class "post-generate-media-button", Html.Events.onClick onClicked ] [ text "Generate Media…" ]

            else
                text ""

        _ ->
            text ""


{-| `mediaEditButton`'s companion in `postDetail`'s media block, on its own
row directly below it (same `isAuthor`-or-`ADMIN` gate, plus only shown once
`post` actually has media to lay out -- an empty gallery has nothing for the
choice to affect) -- a `<select>` letting `post`'s own author pick between
`Components.MultiMediaRenderer`'s two `PostMediaLayout`s (see
`postMediaLayoutText`/`allPostMediaLayouts`). Styled the same as
`visibilityView`/`moderationView`'s own `<select>`s (`.post-visibility-edit
select`/`.post-moderation-edit select` in `posts.css`). Unlike those two
(`Components.Pages.PostPage`'s own edit-mode-with-Save/Cancel flow, needed
there since Save can trip permission checks or permanently set
`publishedAt`), a layout choice has no such side effect worth confirming
first, so this saves immediately on change via `onMediaLayoutChanged` -- the
same one-click immediacy `mediaEditButton`'s own `Shared.MyMediaPanel`
picker already has.
-}
mediaLayoutSelector : Maybe RellmAccount -> (String -> msg) -> Post -> Html msg
mediaLayoutSelector maybeAccount onMediaLayoutChanged post =
    case maybeAccount of
        Just account ->
            if (isAuthor account post || List.member ADMIN account.permissions) && not (List.isEmpty post.media) then
                span [ class "post-media-layout-selector" ]
                    [ span [ class "post-media-layout-label" ] [ text "Media Layout: " ]
                    , select [ Html.Events.onInput onMediaLayoutChanged ]
                        (allPostMediaLayouts
                            |> List.map
                                (\layout ->
                                    option
                                        [ value (postMediaLayoutText layout)
                                        , selected (post.postMediaLayout == layout)
                                        ]
                                        [ text (postMediaLayoutText layout) ]
                                )
                        )
                    ]

            else
                text ""

        Nothing ->
            text ""


{-| Compact rendering for a list of posts from multiple servers at once (see
the Home page's feed) -- shows which server a post is from, since that isn't
otherwise obvious once posts from several are mixed together by recency. Tinted
with `postServerHost`'s `primaryAnchorColor` border (see `UI.EmittedStylesheet`'s
`border-color-primary-anchor-50`/`hover-border-color-primary-anchor` utility
classes) -- faint normally, filling in on hover since the whole card is a link
-- so that's obvious at a glance too.

`current` marks this card as the one for the Post currently being viewed
(see `Shared.StarredPanel.view`, called from `UI.elm` with the current
route's post already resolved) -- filling the whole card with
`postServerHost`'s `primaryColor`/`primaryTextColor` (the `background-color-primary`
utility class) rather than just tinting its border, so it stands out from the
rest of the (unopened) Starred panel at a glance.

The card as a whole isn't a single enclosing `<a>` (despite looking/behaving
like one) -- `authorLink` needs to be a _real_, independently-clickable link of
its own, and nesting an `<a>` inside an `<a>` doesn't work in Elm: every
anchor's `href` navigation is wired up by `elm/browser` as its own native click
listener attached directly to that anchor's DOM node (see `_VirtualDom_divertHrefToApp`
in the compiled runtime), not by walking up to the nearest enclosing `<a>` --
so a click on a nested author link would fire _both_ listeners (author's, then
bubbling up to the card's), and since both call `preventDefault`/navigate, the
outer (later) one always wins and the author link would silently just open the
post instead. Instead this uses the "stretched link" pattern: the first child
below is an invisible `<a>` (`.post-card-link-overlay`) absolutely filling the
whole `.post-card`, sitting _behind_ the title/meta content (`position:
relative` on `.post-card-meta` -- title needs none, see its own lack of
interactive descendants -- stacks it above the overlay per normal CSS painting
order) with `.post-card-meta`'s own `pointer-events: none` (see `posts.css`)
making its plain text transparent to clicks, which fall through to the overlay
below -- while `authorLink`/`starButton`, both opted back in via
`pointer-events: auto`, catch clicks themselves before they ever reach it.

`.post-card-link` (the post's own `link` field, shown below the title via
`postLinkText` when set -- see `posts.css`) needs the same independent-click
treatment as `authorLink`/`starButton`, just via `position: relative` directly
on the anchor rather than the `pointer-events` dance: unlike the title (inert,
so it's fine to just fall through to the overlay behind it and open the post
either way), this one navigates somewhere else entirely, so it needs to win
the overlay's paint order itself.

`extraSmallMedia` shrinks the media preview's height further still (see
`MultiMediaRenderer.previewExtraSmall`) -- for `Shared.StarredPanel`'s
post rows, tighter on vertical space than the Home page's own feed of these
same cards.

`showSyncDestinations`/`availableSyncDestinations`/`isPushing`/`pushError`/`onPush`/`onDelete`
mirror `Components.Events.eventCard`'s own trailing params of the same name/shape exactly (just
without an `Events`-style `showSyncSource`/`syncSourceView` pair -- a plain Post _can_ now have a
"synced from" `SyncSource` too, an RSS/Atom feed item (see `posts.proto`'s `Post.sync_source`),
but no card here surfaces it yet the way `Events.syncSourceView` does for a synced `Event`) --
`showSyncDestinations` gates `postSyncDestinationsView` at the
bottom of the card, the rest thread straight into that call. `availableSyncDestinations` is
`Nothing` for every caller except `Components.Pages.UserProfilePage`'s embedded posts feed, so
push/delete controls render nowhere else. Ignored entirely by the `REPLY` fallback to `replyCard`
below -- a reply is never synced to anything.

-}
postCard : SharedTime.Model -> String -> String -> String -> Maybe RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaRenderer.Model -> (String -> msg) -> Bool -> Bool -> Bool -> Maybe msg -> Bool -> Maybe (List SyncDestination) -> (String -> Bool) -> (String -> Maybe String) -> (String -> msg) -> (String -> String -> msg) -> Post -> Html msg
postCard time basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked extraSmallMedia current starred onStarClicked showSyncDestinations availableSyncDestinations isPushing pushError onPush onDelete post =
    if post.context == REPLY then
        replyCard basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked 0 True False False Nothing Nothing Nothing post

    else
        postCardView time basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked extraSmallMedia current starred onStarClicked showSyncDestinations availableSyncDestinations isPushing pushError onPush onDelete post


{-| The plain (non-`REPLY`) rendering `postCard` falls back to -- see its own
doc comment above for why `REPLY` posts instead defer entirely to
`replyCard`.
-}
postCardView : SharedTime.Model -> String -> String -> String -> Maybe RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaRenderer.Model -> (String -> msg) -> Bool -> Bool -> Bool -> Maybe msg -> Bool -> Maybe (List SyncDestination) -> (String -> Bool) -> (String -> Maybe String) -> (String -> msg) -> (String -> String -> msg) -> Post -> Html msg
postCardView time basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked extraSmallMedia current starred onStarClicked showSyncDestinations availableSyncDestinations isPushing pushError onPush onDelete post =
    div
        [ classes
            ([ "post-card"
             , hostnameToCSSClass postServerHost
             , "border-color-primary-anchor-50"
             , "hover-border-color-primary-anchor"
             ]
                ++ (if isFederatedHost postServerHost then
                        [ "post-card-federated" ]

                    else
                        []
                   )
                ++ (if current then
                        [ "post-card-current", "background-color-primary" ]

                    else
                        [ "background-color-primary-5" ]
                   )
            )
        ]
        [ a
            [ href (postHref basePath viewingServerHost postServerHost post)
            , class "post-card-link-overlay"
            , attribute "aria-label" (postTitleText post)
            ]
            []
        , if isFederatedHost postServerHost then
            text ""

          else
            div [ class "post-card-title" ] [ text (postTitleText post) ]
        , if isFederatedHost postServerHost then
            text ""

          else
            case postLinkText post of
                Just link ->
                    a
                        [ href link
                        , target "_blank"
                        , rel "noopener noreferrer"
                        , classes [ hostnameToCSSClass postServerHost, "post-card-link" ]
                        ]
                        [ text (stripLinkScheme link) ]

                Nothing ->
                    text ""
        , if hasHiddenSensitiveMedia post then
            div [ class "post-card-sensitive-media-notice" ] [ text "This post contains sensitive media. Click to view." ]

          else
            case mediaServer maybeServer postServerHost of
                Just server ->
                    if extraSmallMedia then
                        MultiMediaRenderer.previewExtraSmall server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked post.media

                    else
                        MultiMediaRenderer.preview server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked post.media

                Nothing ->
                    text ""
        , case post.content of
            Just content ->
                Markdown.view
                    [ classes
                        (if String.length content > contentPreviewFadeThreshold then
                            [ "post-card-content-preview", "post-card-content-preview-fade" ]

                         else
                            [ "post-card-content-preview" ]
                        )
                    ]
                    content

            Nothing ->
                text ""
        , div [ class "post-card-meta" ]
            [ span [ class "post-meta-left" ]
                ((if isFederatedHost postServerHost then
                    [ text "⇄ " ]

                  else
                    []
                 )
                    ++ [ Authors.link basePath viewingServerHost postServerHost maybeServer maybeAccount post.author
                       , text
                            ((if postServerHost == viewingServerHost then
                                ""

                              else
                                " · " ++ displayHost postServerHost
                             )
                                ++ (if showPostVisibility maybeAccount post then
                                        " · " ++ postVisibilityText post

                                    else
                                        ""
                                   )
                            )
                       ]
                )
            , span [ class "post-meta-right" ]
                [ timestampsText time post
                , starButton postServerHost starred onStarClicked post
                , text (commentCountText post)
                ]
            ]
        , if showSyncDestinations then
            postSyncDestinationsView availableSyncDestinations isPushing pushError onPush onDelete post

          else
            text ""
        ]


{-| A single reply's card -- author, content, a Reply button, and (bottom
right of the actions row) a merged load-more/collapse-expand button carrying
`post`'s own reply/response counts (see `replyStatusButton`). `depth` (1 for a
direct reply, 2 for a reply to a reply, etc.) drives its left-indentation, so
`Components.PostReplies.view`'s flattened list still reads as a nested thread.

`onReplyClicked`/`onLoadRepliesClicked`/`onToggleCollapsedClicked` are each
`Maybe msg` rather than plain `msg` so a caller with no real handler for one
(`postCard`'s own `REPLY`-context fallback above, which has no reply-thread
state to drive these at all) can pass `Nothing` and get that action's
button omitted entirely, rather than needing to fabricate a message value
that can never actually fire.

-}
replyCard :
    String
    -> String
    -> String
    -> Maybe RellmServer
    -> Maybe RellmAccount
    -> (String -> msg)
    -> MediaRenderer.Model
    -> (String -> msg)
    -> Int
    -> Bool
    -> Bool
    -> Bool
    -> Maybe msg
    -> Maybe msg
    -> Maybe msg
    -> Post
    -> Html msg
replyCard basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked depth loaded loading collapsed onReplyClicked onLoadRepliesClicked onToggleCollapsedClicked post =
    div
        [ class "post-reply-item"
        , style "margin-left" (String.fromInt (min depth 8 * 20) ++ "px")
        ]
        [ div [ class "post-reply-meta" ]
            [ span [ class "post-meta-left" ]
                (Authors.link basePath viewingServerHost postServerHost maybeServer maybeAccount post.author
                    :: (if showPostVisibility maybeAccount post then
                            [ text (" · " ++ postVisibilityText post) ]

                        else
                            []
                       )
                )
            , span [ class "post-meta-right" ]
                [ a
                    [ href (postHref basePath viewingServerHost postServerHost post)
                    , class "post-reply-permalink"
                    , attribute "aria-label" "Permalink"
                    ]
                    [ text "🔗" ]
                ]
            ]
        , if hasHiddenSensitiveMedia post then
            a
                [ href (postHref basePath viewingServerHost postServerHost post)
                , class "post-reply-sensitive-media-notice"
                ]
                [ text "This post contains sensitive media. Click to view." ]

          else
            case mediaServer maybeServer postServerHost of
                Just server ->
                    MultiMediaRenderer.previewExtraSmall server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked post.media

                Nothing ->
                    text ""
        , case post.content of
            Just content ->
                Markdown.view [ class "post-reply-content" ] content

            Nothing ->
                text ""
        , div [ class "post-reply-actions" ]
            [ case ( maybeAccount, onReplyClicked ) of
                ( Just account, Just msg ) ->
                    if List.member REPLYTOPOSTS account.permissions then
                        button [ class "post-reply-button", Html.Events.onClick msg ] [ text "Reply" ]

                    else
                        text ""

                _ ->
                    text ""
            , replyStatusButton loaded loading collapsed onLoadRepliesClicked onToggleCollapsedClicked post
            ]
        ]


{-| The merged "load more"/"collapse"/"expand" button in a reply card's
bottom-right corner (`.post-reply-status-button`, pinned right via
`margin-left: auto` same as `.post-meta-right`), carrying `post`'s own
reply/response counts (`repliesCountText`, matching `commentCountText`'s own
formatting) in each of its three states:

  - still more to fetch (`post.replies`'s length doesn't yet match
    `post.replyCount`, and this node hasn't been explicitly `ReplyLoaded`):
    "Load 💬 X/Y More" (or a "Loading replies…" placeholder while `loading`),
    firing `onLoadRepliesClicked` (if supplied)
  - fully loaded and has any replies: an Expand/Collapse toggle (driven by
    `collapsed`) firing `onToggleCollapsedClicked` (if supplied)
  - fully loaded with no replies at all, or no handler supplied for the
    state it's in: nothing

-}
replyStatusButton : Bool -> Bool -> Bool -> Maybe msg -> Maybe msg -> Post -> Html msg
replyStatusButton loaded loading collapsed onLoadRepliesClicked onToggleCollapsedClicked post =
    let
        fullyLoaded : Bool
        fullyLoaded =
            loaded || List.length post.replies == post.replyCount

        countText : String
        countText =
            "💬 " ++ repliesCountText post
    in
    if fullyLoaded then
        if List.isEmpty post.replies then
            text ""

        else
            case onToggleCollapsedClicked of
                Just msg ->
                    button
                        [ class "post-reply-status-button", Html.Events.onClick msg ]
                        [ text
                            -- ▲/▼ ◀/▶
                            ((if collapsed then
                                "▶ "

                              else
                                "▼ "
                             )
                                ++ countText
                            )
                        ]

                Nothing ->
                    text ""

    else if loading then
        span [ class "post-reply-loading" ] [ text "Loading replies…" ]

    else
        case onLoadRepliesClicked of
            Just msg ->
                button
                    [ class "post-reply-status-button", Html.Events.onClick msg ]
                    [ text ("Load " ++ countText ++ " More") ]

            Nothing ->
                text ""


{-| Full rendering for a single post (see the Post page) -- still tinted with
`postServerHost`'s `primaryAnchorColor` border like `postCard` is (just
without the hover fill-in, since this one isn't a link). `onEditClicked`
drives `editButton`, shown in the meta line's `post-meta-right` group only to
the post's own author.

Only a plain `POST` gets a title at all -- a `REPLY`/`EVENT`/etc. has no real
title of its own (`postTitleText`'s fallback to a truncated `content` exists
for contexts, like `postCard`'s feed entries, where _something_ short is
needed regardless; here, with the full `content` rendered right below anyway,
that fallback would just be a redundant near-duplicate of it). It gets
`postContextLabel`'s small context chip in its place instead (mirroring
`Shared.StarredPanel`'s own `starred-post-context`) -- since a Post
reached this way is, on `Pages.Post.PostId_`, already headed by
`Shared.Breadcrumbs`' own trail showing exactly _which_ reply this is, this
chip only needs to mark plainly _that_ it's one, not repeat any of that
context.

`visibilityView` is the whole visibility segment of the meta line -- plain
text (the common case) or an in-progress `<select>` editor, entirely up to
the caller (`Pages.Post.PostId_`, which owns the editing state/permission
gating for it, the same way it owns `onEditClicked`) -- this just slots
whatever `Html` it's given in after the author link, in place of what used to
be a bare `postVisibilityText post` text node. `moderationView` is the same
idea, slotted right after it, for the (Admin-/`MODERATEPOSTS`-only)
moderation-status segment.

`onGenerateMediaClicked` drives `generateMediaButton`, shown alongside `mediaEditButton` in the same
row -- `Nothing` if the caller has no reason to offer it (no image-capable `AIModel`, or
the viewer isn't `post`'s author/an Admin; see that button's own doc).

`onMediaLayoutChanged` drives `mediaLayoutSelector`, shown below
`mediaEditButton` in the media block -- unlike `visibilityView`/
`moderationView`, this one's a plain callback rather than caller-supplied
`Html`, since (per `mediaLayoutSelector`'s own doc) it has no separate
edit-mode/Save/Cancel state for the caller to own; it saves on every change.

`availableSyncDestinations`/`isPushing`/`pushError`/`onPush`/`onDelete` drive an always-shown
`postSyncDestinationsView` at the bottom of the detail view, mirroring
`Pages.Event.PostId_`'s own `Events.eventSyncDestinationsView` call exactly -- `Nothing` until the
caller's own fetch of the viewer's `SyncDestination`s (gated on being `post`'s author or Admin)
resolves, same `Nothing`-falls-back-to-read-only-links behavior as that page (see
`Components.Pages.PostPage.Model.availableSyncDestinations`'s own doc for the fetch itself).

`readOnly`, when `True`, hides every edit affordance this would otherwise show its own author/an
Admin (`mediaEditButton`/`generateMediaButton`/`mediaLayoutSelector`/`editContentButton` all become
`text ""` outright, regardless of `maybeAccount`) and turns the title into a link to the post's own
`/post/:id` page (`postHref`) -- for a caller rendering a Post somewhere other than its own dedicated
page (currently just `Components.PinnedPosts`, which has no edit-state of its own to wire those
buttons to -- see its own doc) where a viewer who happens to own the Post should go edit it on that
canonical page instead, not expect a half-wired Edit button to work in place. `maybeAccount` itself is
untouched by this flag -- `Authors.link`/`MultiMediaRenderer.view` still get the real value, so
private/limited media and author badges keep working normally; only the edit-gating call sites above
are skipped.

`contentCollapse`, when `Just`, lets the content Markdown itself be clamped to a short,
`postDetailContentPreviewHeight`-tall preview (`collapse.toggle` fired by a "Show more"/"Show less"
link below it, `collapse.collapsed` reflecting the caller's own current choice, `collapse.naturalHeight`
the content's own real full height so the clamp can animate smoothly between the two rather than
snapping) rather than always rendering in full -- currently only `Components.PinnedPosts` passes this
(see its own `contentHeights`/`expandedPostIds`), since a pin is meant to be glanceable without
necessarily reading its entire content; `Nothing` (every other caller, e.g. `Components.Pages.PostPage`,
a Post's own dedicated page) always renders the content in full, with no toggle at all. See
`postDetailContentView`'s own doc for why _whether_ to offer the toggle at all is left entirely to the
caller's own measurement, not decided in here.

-}
postDetail : SharedTime.Model -> String -> String -> String -> Maybe RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaRenderer.Model -> (String -> msg) -> Bool -> msg -> Maybe msg -> (String -> msg) -> Bool -> Maybe msg -> msg -> Html msg -> Html msg -> Maybe (List SyncDestination) -> (String -> Bool) -> (String -> Maybe String) -> (String -> msg) -> (String -> String -> msg) -> Maybe (ContentCollapse msg) -> Post -> Html msg
postDetail time basePath viewingServerHost postServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked readOnly onMediaEditClicked onGenerateMediaClicked onMediaLayoutChanged starred onStarClicked onEditClicked visibilityView moderationView availableSyncDestinations isPushing pushError onPush onDelete contentCollapse post =
    div [ classes [ "post-detail", hostnameToCSSClass postServerHost, "border-color-primary-anchor-50" ] ]
        [ div [ class "post-detail-title-row" ]
            [ if post.context == POST then
                let
                    titleHeading : Html msg
                    titleHeading =
                        h1 [ class "post-detail-title" ] [ text (postTitleText post) ]
                in
                if readOnly then
                    a
                        [ href (postHref basePath viewingServerHost postServerHost post)
                        , class "post-detail-title-link"
                        ]
                        [ titleHeading ]

                else
                    titleHeading

              else
                case postContextLabel post.context of
                    Just contextLabel ->
                        div [ class "post-detail-context" ] [ text contextLabel ]

                    Nothing ->
                        text ""
            ]
        , case postLinkText post of
            Just link ->
                a
                    [ href link
                    , target "_blank"
                    , rel "noopener noreferrer"
                    , classes [ hostnameToCSSClass postServerHost, "post-detail-link" ]
                    ]
                    [ text (stripLinkScheme link) ]

            Nothing ->
                text ""
        , case maybeServer of
            Just server ->
                div []
                    [ MultiMediaRenderer.view post.postMediaLayout server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked post.media
                    , if readOnly then
                        text ""

                      else
                        div [ class "post-detail-media-edit-row" ]
                            [ mediaEditButton maybeAccount onMediaEditClicked post
                            , generateMediaButton maybeAccount onGenerateMediaClicked post
                            ]
                    , if readOnly then
                        text ""

                      else
                        div [ class "post-detail-media-layout-row" ] [ mediaLayoutSelector maybeAccount onMediaLayoutChanged post ]
                    ]

            Nothing ->
                text ""
        , div [ class "post-detail-meta" ]
            [ span [ class "post-meta-left" ]
                [ text "by "
                , Authors.link basePath viewingServerHost postServerHost maybeServer maybeAccount post.author
                , visibilityView
                , moderationView
                ]
            , span [ class "post-meta-right" ]
                [ timestampsText time post
                , starButton postServerHost starred onStarClicked post
                , text (commentCountText post)
                ]
            ]
        , case post.content of
            Just content ->
                postDetailContentView contentCollapse post.id content

            Nothing ->
                text ""
        , if readOnly then
            text ""

          else
            div [ class "post-detail-edit-row" ] [ editContentButton maybeAccount onEditClicked post ]
        , postSyncDestinationsView availableSyncDestinations isPushing pushError onPush onDelete post
        ]


{-| `postDetail`'s own `contentCollapse` argument -- see that parameter's own doc. `naturalHeight` is
the content's real, full (unclamped) rendered height in px, as the caller measured it (currently
always via `Ports.measureElements`, see `Components.PinnedPosts.kickOffContentMeasurements`) --
`postDetailContentView` clamps `max-height` to this exact value rather than removing the clamp
outright when `collapsed == False`, purely so the CSS `transition` on `max-height` has two concrete
px values to animate between (a transition into/out of `none`/`auto` doesn't animate in CSS at all).
-}
type alias ContentCollapse msg =
    { collapsed : Bool
    , toggle : msg
    , naturalHeight : Float
    }


{-| `postDetail`'s own content block -- `contentCollapse`'s own doc. Always rendered at `postId`'s own
`postDetailContentDomId` regardless of `contentCollapse`, so a caller that wants the toggle (currently
just `Components.PinnedPosts`) can measure this element's real rendered height (via `Ports.measureElements`)
to decide whether it's actually taller than `postDetailContentPreviewHeight` -- raw Markdown length
alone doesn't predict that reliably (a handful of short paragraphs/headings/list items can render far
taller than a single 400-character one, and vice versa for a long paragraph that wraps to only two or
three lines), so this renders in full, with no toggle, until the caller has actually measured it and
found it worth clamping -- exactly `postDetail` always rendered before this existed. `Just collapse`
(only once the caller's own measurement confirms it's tall enough to matter) renders `content` itself
(clamped to `postDetailContentPreviewHeight` when `collapse.collapsed`, `collapse.naturalHeight`
otherwise -- both concrete `max-height` px values, so the `post-detail-content-collapsible`'s own CSS
`transition` can animate the toggle instead of snapping) plus a "Show more"/"Show less" button below
it.
-}
postDetailContentView : Maybe (ContentCollapse msg) -> String -> String -> Html msg
postDetailContentView contentCollapse postId content =
    case contentCollapse of
        Just collapse ->
            div [ class "post-detail-content-collapsible" ]
                [ Markdown.view
                    [ id (postDetailContentDomId postId)
                    , classes
                        ("post-detail-content"
                            :: (if collapse.collapsed then
                                    [ "post-detail-content-collapsed" ]

                                else
                                    []
                               )
                        )
                    , style "max-height"
                        (String.fromFloat
                            (if collapse.collapsed then
                                postDetailContentPreviewHeight

                             else
                                -- +1px headroom so a sub-pixel rounding difference between the
                                -- measured `naturalHeight` and the real layout can't leave a
                                -- fraction of a line clipped off even while "expanded".
                                collapse.naturalHeight + 1
                            )
                            ++ "px"
                        )
                    ]
                    content
                , button
                    [ class "post-detail-content-toggle", Html.Events.onClick collapse.toggle ]
                    [ text
                        (if collapse.collapsed then
                            "Show more"

                         else
                            "Show less"
                        )
                    ]
                ]

        Nothing ->
            Markdown.view [ id (postDetailContentDomId postId), class "post-detail-content" ] content


{-| The DOM `id` `postDetailContentView` renders its content block at, for `postId` -- exists so a
caller measuring it (see `postDetailContentView`'s own doc) doesn't have to reconstruct this string
itself/risk drifting out of sync with it.
-}
postDetailContentDomId : String -> String
postDetailContentDomId postId =
    "post-detail-content-" ++ postId


{-| The `max-height` (px) `postDetailContentView` clamps a collapsed preview to -- also what
`Components.PinnedPosts` compares a measured `ContentCollapse.naturalHeight` against to decide whether
a pinned post's content is worth offering the toggle for at all (see `postDetailContentView`'s own
doc). Kept here (rather than duplicated as a raw `100` in both modules, or in `posts.css`) since it's
inherently a contract between this view and whatever measures against it.
-}
postDetailContentPreviewHeight : Float
postDetailContentPreviewHeight =
    180



-- ROUTE / LINKS


{-| The href for `post`, as seen from `viewingServerHost` (typically
`shared.accounts.mainFrontendHost`) -- a post on that same server links
as plain `/post/:id`; anything else includes its host, `/post/:id@host`, so
`Pages.Post.PostId_` knows which server to fetch it from. `basePath` is
`Shared.Model.basePath`, same as `UI.navLink`.
-}
postHref : String -> String -> String -> Post -> String
postHref basePath viewingServerHost postServerHost post =
    let
        postId : String
        postId =
            if postServerHost == viewingServerHost then
                post.id

            else
                post.id ++ "@" ++ postServerHost
    in
    basePath ++ Gen.Route.toHref (Gen.Route.Post__PostId_ { postId = postId })



-- DISPLAY


postTitleText : Post -> String
postTitleText post =
    case Maybe.map String.trim post.title of
        Just title ->
            if String.isEmpty title then
                fallbackTitle post

            else
                title

        Nothing ->
            fallbackTitle post


{-| The post's `link` field, trimmed -- `Nothing` if unset or blank, same
convention as `postTitleText`'s own trimming (just without a fallback, since
unlike a title, a post with no link simply shows no link row at all).
-}
postLinkText : Post -> Maybe String
postLinkText post =
    post.link
        |> Maybe.map String.trim
        |> Maybe.andThen
            (\link ->
                if String.isEmpty link then
                    Nothing

                else
                    Just link
            )


{-| `link` with a leading `http://`/`https://` dropped, for display only --
callers still `href` the untouched `postLinkText` value, this is just to
avoid stating the obvious (every post link is one or the other) and buy back
a few more characters before `.post-card-link`/`.post-detail-link`'s
`text-overflow: ellipsis` kicks in.
-}
stripLinkScheme : String -> String
stripLinkScheme link =
    if String.startsWith "https://" link then
        String.dropLeft 8 link

    else if String.startsWith "http://" link then
        String.dropLeft 7 link

    else
        link


fallbackTitle : Post -> String
fallbackTitle post =
    post.content
        |> Maybe.map (stripHtmlTagsIfPresent >> String.left 60)
        |> Maybe.withDefault "Post"


{-| Strips HTML tags out of `content` before it's ever truncated/shown as plain text (see
`fallbackTitle`) -- a real Rellm post's Markdown source essentially never starts with a literal `<`,
but a Mastodon post's `content` (see `Shared.Federation.Mastodon.toPost`'s own doc) always does, so
that's the same heuristic `markdown.js`'s `looksLikeHtml` uses to skip Markdown-parsing it (that path
runs the content through DOMPurify and renders it as real HTML; this one instead needs a _plain-text_
string, since a card title/page `<h1>` can't render markup at all). A no-op otherwise. Not a full HTML
parser -- just enough for Mastodon's own simple, machine-generated markup (`<p>`, `<br>`,
`<a href=...>`, `<span class=...>`) to read as plain text instead of literal tags.
-}
stripHtmlTagsIfPresent : String -> String
stripHtmlTagsIfPresent content =
    if String.startsWith "<" (String.trimLeft content) then
        stripTagsAndDecodeEntities content

    else
        content


{-| The actual scan `stripHtmlTagsIfPresent` hands off to once it's decided `content` is HTML --
drops everything between `<`/`>` (tags), and decodes character references (`&amp;`, `&#39;`, `&#x27;`,
etc.) back into their literal characters, the same as a browser's own HTML parser would when setting
`innerHTML` (which is what `markdown.js`'s own HTML path relies on for the _rendered_ content -- this
function exists because a plain-text title has no such parser to lean on).
-}
stripTagsAndDecodeEntities : String -> String
stripTagsAndDecodeEntities input =
    case String.uncons input of
        Nothing ->
            ""

        Just ( '<', rest ) ->
            stripTagsAndDecodeEntities (dropThroughTag rest)

        Just ( '&', rest ) ->
            case decodeEntity rest of
                Just ( char, afterEntity ) ->
                    String.cons char (stripTagsAndDecodeEntities afterEntity)

                Nothing ->
                    String.cons '&' (stripTagsAndDecodeEntities rest)

        Just ( char, rest ) ->
            String.cons char (stripTagsAndDecodeEntities rest)


dropThroughTag : String -> String
dropThroughTag input =
    case String.uncons input of
        Nothing ->
            ""

        Just ( '>', rest ) ->
            rest

        Just ( _, rest ) ->
            dropThroughTag rest


{-| Decodes one HTML character reference starting right after its `&` -- e.g. `"amp;rest"` ->
`Just ( '&', "rest" )`, `"#39;rest"` -> `Just ( '\'', "rest" )`. `Nothing` if what follows isn't a
recognized reference (a bare `&` in real text, not an escape), so the `&` gets kept literally instead
of eaten. Only looks within the next 10 characters for a closing `;` -- long enough for any entity
this actually needs to handle, short enough that a stray `&` followed by ordinary prose (which will
often contain a `;` eventually) doesn't get misread as one.
-}
decodeEntity : String -> Maybe ( Char, String )
decodeEntity afterAmp =
    case String.indexes ";" (String.left 10 afterAmp) |> List.head of
        Just semicolonIndex ->
            entityChar (String.left semicolonIndex afterAmp)
                |> Maybe.map (\char -> ( char, String.dropLeft (semicolonIndex + 1) afterAmp ))

        Nothing ->
            Nothing


{-| The handful of character references Mastodon's own HTML-escaping (and, occasionally, a user's
own hand-typed HTML entities before that) actually produces -- the 5 XML-predefined ones, a few
common typographic ones, and numeric references (`#NNN` decimal, `#xHHH`/`#XHHH` hex) generally.
Not a full HTML5 named-entity table (hundreds of entries like `&hellip;`'s less common cousins) --
just enough for real-world Mastodon content to read as plain text instead of literal escapes.
-}
entityChar : String -> Maybe Char
entityChar name =
    case name of
        "amp" ->
            Just '&'

        "lt" ->
            Just '<'

        "gt" ->
            Just '>'

        "quot" ->
            Just '"'

        "apos" ->
            Just '\''

        "nbsp" ->
            Just ' '

        "hellip" ->
            Just '…'

        "mdash" ->
            Just '—'

        "ndash" ->
            Just '–'

        "lsquo" ->
            Just '‘'

        "rsquo" ->
            Just '’'

        "ldquo" ->
            Just '“'

        "rdquo" ->
            Just '”'

        _ ->
            if String.startsWith "#x" name || String.startsWith "#X" name then
                String.dropLeft 2 name |> hexToInt |> Maybe.map Char.fromCode

            else if String.startsWith "#" name then
                String.dropLeft 1 name |> String.toInt |> Maybe.map Char.fromCode

            else
                Nothing


hexToInt : String -> Maybe Int
hexToInt hex =
    if String.isEmpty hex then
        Nothing

    else
        hex
            |> String.toList
            |> List.foldl (\c acc -> acc |> Maybe.andThen (\n -> hexDigit c |> Maybe.map (\d -> n * 16 + d))) (Just 0)


hexDigit : Char -> Maybe Int
hexDigit c =
    case Char.toLower c of
        '0' ->
            Just 0

        '1' ->
            Just 1

        '2' ->
            Just 2

        '3' ->
            Just 3

        '4' ->
            Just 4

        '5' ->
            Just 5

        '6' ->
            Just 6

        '7' ->
            Just 7

        '8' ->
            Just 8

        '9' ->
            Just 9

        'a' ->
            Just 10

        'b' ->
            Just 11

        'c' ->
            Just 12

        'd' ->
            Just 13

        'e' ->
            Just 14

        'f' ->
            Just 15

        _ ->
            Nothing


{-| Display text for a post's visibility, e.g. for a "Public"/"Private"/etc.
badge on its preview.
-}
postVisibilityText : Post -> String
postVisibilityText post =
    visibilityText post.visibility


{-| Whether `post`'s visibility should be shown to a viewer signed in (or not)
to its own server as `maybeAccount` -- hidden only when signed out and the
visibility is the default `GLOBALPUBLIC`, since an anonymous viewer has no way
to tell a `GLOBALPUBLIC` post apart from one with no visibility label at all;
any other visibility, or being signed in, still shows it explicitly (e.g. so
an author can confirm what they set).
-}
showPostVisibility : Maybe RellmAccount -> Post -> Bool
showPostVisibility maybeAccount post =
    case ( maybeAccount, post.visibility ) of
        ( Nothing, GLOBALPUBLIC ) ->
            False

        _ ->
            True


{-| Display text for a bare `Visibility` value -- same mapping
`postVisibilityText` uses for a `Post`'s own, but also needed on its own for
`Pages.Post.PostId_`'s visibility-editing `<select>`, whose options are
`allVisibilities` rather than any particular Post's current value.
-}
visibilityText : Visibility -> String
visibilityText visibility =
    case visibility of
        PRIVATE ->
            "Private"

        LIMITED ->
            "Limited"

        SERVERPUBLIC ->
            "Server Public"

        GLOBALPUBLIC ->
            "Global Public"

        DIRECT ->
            "Direct"

        VISIBILITYUNKNOWN ->
            "Unknown"

        VisibilityUnrecognized_ _ ->
            "Unknown"


{-| A human-facing label for a Post's `context` when it's something other than
a plain `POST` (a `Reply`, `Event`, `Occasion`, etc.) -- `Nothing` for a
plain `POST`, since that's the common case and doesn't need calling out
wherever a Post is shown alongside its context (see
`Shared.StarredPanel`'s panel view).
-}
postContextLabel : PostContext -> Maybe String
postContextLabel context =
    case context of
        POST ->
            Nothing

        REPLY ->
            Just "Reply"

        EVENT ->
            Just "Event"

        OCCASION ->
            Nothing

        FEDERATEDREPLY ->
            Just "Federated Reply"

        PostContextUnrecognized_ _ ->
            Nothing


{-| A post's reply-count display: just `responseCount` when `replyCount`
(direct replies only) and `responseCount` (all nested replies) agree -- the
common case, a post with no replies-to-replies -- otherwise
`"replyCount/responseCount"` (e.g. `"20/25"`) so a thread with actual
sub-discussion shows both numbers at a glance. Shared by `commentCountText`
(below, for `postCard`/`postDetail`) and `replyCard`, so a reply card's own
count matches a post card's exactly.
-}
repliesCountText : Post -> String
repliesCountText post =
    if post.replyCount == post.responseCount then
        String.fromInt post.responseCount

    else
        String.fromInt post.replyCount ++ "/" ++ String.fromInt post.responseCount


{-| "· 💬 12"-style suffix for a post's meta line, following `starButton`.
-}
commentCountText : Post -> String
commentCountText post =
    " · 💬 " ++ repliesCountText post


{-| Whether `account` is `post`'s own author -- e.g. to show an Edit button
only to the post's author (see `Pages.Post.PostId_`). `False` if the post has
no `author` at all (shouldn't normally happen, but `Post.author` is optional).
-}
isAuthor : RellmAccount -> Post -> Bool
isAuthor account post =
    Maybe.map .userId post.author == Just account.userId


{-| The inverse of `postHref`: `rawPostId` is either a bare id (a post on
`mainFrontendHost`) or `id@host` (a post on some other, federated server).
-}
parsePostRouteId : String -> String -> ( String, String )
parsePostRouteId mainFrontendHost rawPostId =
    case String.split "@" rawPostId of
        [ id, host ] ->
            ( id, host )

        _ ->
            ( rawPostId, mainFrontendHost )


{-| Recognizes a Mastodon/Bluesky post from `parsePostRouteId`'s own `( id, host )` pair -- `host` is
what actually carries the `"mastodon:"`/`"bluesky:"` tag here (see
`Components.Pages.PostsPage.feedSourceKey`'s own construction, and `Shared.Federation.Mastodon`/
`Bluesky`'s own `toPost`, whose `id` is deliberately just the bare platform id/URI with no such
prefix of its own -- see either's doc for why), so this picks `instanceHost`/`uri` back apart from
`host`, pairing it with `id` verbatim, into whatever `Shared.Federation.Mastodon.fetchStatus`/
`Shared.Federation.Bluesky.fetchPost` need to look the post back up directly -- no Rellm server
involved at all, unlike a real post's `GetPosts` fetch. `Nothing` for a real Rellm post's own
`host` (or anything else unrecognized). `Components.Pages.PostPage.init` is the one caller -- see its
own doc for why a federated post gets an entirely separate, read-only fetch/view path.
-}
type FederatedPostId
    = MastodonPostId { instanceHost : String, statusId : String }
    | BlueskyPostId { uri : String }


parseFederatedPostId : String -> String -> Maybe FederatedPostId
parseFederatedPostId id host =
    if String.startsWith "mastodon:" host then
        Just (MastodonPostId { instanceHost = String.dropLeft 9 host, statusId = id })

    else if String.startsWith "bluesky:" host then
        Just (BlueskyPostId { uri = id })

    else
        Nothing


{-| Like `parseFederatedPostId /= Nothing`, but without needing a (usually irrelevant) `id` alongside
`host` -- `postCardView` uses this to hide the title/link row for a Mastodon/Bluesky post's card
(its own "View original" link lives only on the detail page, via `Components.Pages.MastodonPostPage`/
`BlueskyPostPage`) and to mark its author row with "⇄".
-}
isFederatedHost : String -> Bool
isFederatedHost host =
    String.startsWith "mastodon:" host || String.startsWith "bluesky:" host


{-| `maybeServer` as-is, or (once it's `Nothing` and `postServerHost` is federated) a placeholder
`RellmServer` for `postCardView`/`replyCard`'s own `MultiMediaRenderer` calls -- never actually
dereferenced by `Components.MediaRenderer.authorizedUrl`, since a federated post's `media` is always
`.url`-only, externally-hosted `MediaReference`s (see that function's own doc). Without this, a
federated post's card would always render no media at all: its own synthetic `"mastodon:"`/
`"bluesky:"` `postServerHost` never matches a real connected `RellmServer`
(`RellmServers.rellmServerForHost`), so `maybeServer` itself is always `Nothing` here, same as a real
Rellm post whose server genuinely isn't resolved yet -- this is what tells the two apart.
-}
mediaServer : Maybe RellmServer -> String -> Maybe RellmServer
mediaServer maybeServer postServerHost =
    case maybeServer of
        Just server ->
            Just server

        Nothing ->
            if isFederatedHost postServerHost then
                Just { frontendHost = "", enabled = False, connected = Nothing, sortOrder = 0 }

            else
                Nothing


{-| Whether `post.media` is `Shared.Federation.Mastodon`/`Bluesky`'s own
`sensitiveMediaHiddenPlaceholder` -- a `sensitive`-flagged federated post's real media, deliberately
left out of every feed/card context (see either module's `toPostWith`' own doc) since Rellm has no
NSFW-filtering concept of its own to render it behind. `postCardView`/`replyCard` check this to show
a "This post contains sensitive media" notice instead of silently rendering nothing, in place of
their usual `MultiMediaRenderer` call -- clicking through (the whole card is already one big link, see
`postCardView`'s own `.post-card-link-overlay`) reaches `Components.Pages.MastodonPostPage`/
`BlueskyPostPage`, the only place this post's media actually renders (via `toPostIncludingSensitiveMedia`).
-}
hasHiddenSensitiveMedia : Post -> Bool
hasHiddenSensitiveMedia post =
    List.any (\media -> media.id == sensitiveMediaHiddenId) post.media


{-| `host` as shown next to a post card -- strips the `"mastodon:"`/`"bluesky:"` tag `isFederatedHost`
itself looks for (see `parseFederatedPostId`'s own doc on why it's there), since that tag exists only
to keep this synthetic host from colliding with a real Rellm `frontendHost`, not to be shown to a
user reading "posted on mastodon.world". A real Rellm `host` (never carrying either prefix) passes
through unchanged.
-}
displayHost : String -> String
displayHost host =
    if String.startsWith "mastodon:" host then
        String.dropLeft 9 host

    else if String.startsWith "bluesky:" host then
        String.dropLeft 8 host

    else
        host


{-| A post's most relevant timestamp for "recency" sorting/display: when it
was published, falling back to when it was created (drafts, or servers that
don't distinguish the two).
-}
postTimestamp : Post -> Time.Posix
postTimestamp post =
    case ( post.publishedAt, post.createdAt ) of
        ( Just ts, _ ) ->
            timestampToPosix ts

        ( Nothing, Just ts ) ->
            timestampToPosix ts

        ( Nothing, Nothing ) ->
            Time.millisToPosix 0


{-| The visibility options offered by a visibility-editing `<select>` (see
`Pages.Post.PostId_`) -- excludes `DIRECT`, which the proto itself marks
`[TODO]`/unimplemented (see `protos/visibility_moderation.proto`), and
`VISIBILITYUNKNOWN`, which is never a valid value to _set_. Order matches
`visibilityText`/the proto's own declaration order.
-}
allVisibilities : List Visibility
allVisibilities =
    [ PRIVATE, LIMITED, SERVERPUBLIC, GLOBALPUBLIC ]


{-| The reverse of `visibilityText` -- looks up a `Visibility` by its display
label, the same round-trip `Components.Users.permissionFromText` does for
`Permission` -- needed because a plain HTML `<select>`'s value/`onInput` are
just strings. `Nothing` for any text that isn't one of `allVisibilities`'
labels (shouldn't happen, since the `<select>`'s own options are always built
from `allVisibilities` in the first place).
-}
visibilityFromText : String -> Maybe Visibility
visibilityFromText text =
    allVisibilities |> List.filter (\visibility -> visibilityText visibility == text) |> List.head


{-| The options offered by `mediaLayoutSelector`'s `<select>` -- every real
`PostMediaLayout` (excludes `PostMediaLayoutUnrecognized_`, never a valid
value to _set_). Order matches `posts.proto`'s own declaration order.
-}
allPostMediaLayouts : List PostMediaLayout
allPostMediaLayouts =
    [ MEDIALAYOUTSTANDARD, MEDIALAYOUTDYNAMICVERTICALSCROLL ]


{-| Display text for a `PostMediaLayout` -- both `mediaLayoutSelector`'s
`<select>` options (built from `allPostMediaLayouts`) and its own current
selection. `PostMediaLayoutUnrecognized_` falls back to the standard
layout's own label, same as an unset/zero-value field would decode to.
-}
postMediaLayoutText : PostMediaLayout -> String
postMediaLayoutText layout =
    case layout of
        MEDIALAYOUTSTANDARD ->
            "Standard"

        MEDIALAYOUTDYNAMICVERTICALSCROLL ->
            "Dynamic Vertically-Scrolling"

        PostMediaLayoutUnrecognized_ _ ->
            "Standard"


{-| The reverse of `postMediaLayoutText` -- same `<select>`-value round-trip
`visibilityFromText` does for `Visibility`.
-}
postMediaLayoutFromText : String -> Maybe PostMediaLayout
postMediaLayoutFromText text =
    allPostMediaLayouts |> List.filter (\layout -> postMediaLayoutText layout == text) |> List.head


{-| The moderation-status options offered by a moderation-editing `<select>`
(see `Pages.Post.PostId_`/`Pages.Event.PostId_`'s own moderation selectors)
-- excludes `MODERATIONUNKNOWN`, never a valid value to _set_. Order matches
the proto's own declaration order.
-}
allModerations : List Moderation
allModerations =
    [ UNMODERATED, PENDING, APPROVED, REJECTED ]


{-| The reverse of `Components.Users.moderationText` -- same `<select>`-value
round-trip `visibilityFromText` does for `Visibility`.
-}
moderationFromText : String -> Maybe Moderation
moderationFromText text =
    allModerations |> List.filter (\moderation -> Users.moderationText moderation == text) |> List.head


{-| Which of `allVisibilities` `account` may pick for a Post/Event/etc. of
`context` -- mirrors `backend/src/rpcs/posts/update_post.rs`'s own permission
check: setting `SERVERPUBLIC`/`GLOBALPUBLIC` needs `PUBLISHPOSTSLOCALLY`/
`PUBLISHPOSTSGLOBALLY` for a plain `POST`/`REPLY`, or `PUBLISHEVENTSLOCALLY`/
`PUBLISHEVENTSGLOBALLY` for an `EVENT`/`OCCASION` -- `ADMIN` always
passes either. `currentVisibility` is always included even if it wouldn't
otherwise be pickable, so an account whose permission was revoked after the
post was already elevated still sees its own current value in the list
(just can't newly pick it for some _other_ post) -- see
`Pages.Post.PostId_`'s visibility editor, which seeds its pending value from
the post's already-current one.
-}
allowedVisibilities : List Permission -> PostContext -> Visibility -> List Visibility
allowedVisibilities permissions context currentVisibility =
    let
        isEventContext : Bool
        isEventContext =
            context == EVENT || context == OCCASION

        has : Permission -> Bool
        has permission =
            List.member permission permissions || List.member ADMIN permissions

        canPublishLocally : Bool
        canPublishLocally =
            has
                (if isEventContext then
                    PUBLISHEVENTSLOCALLY

                 else
                    PUBLISHPOSTSLOCALLY
                )

        canPublishGlobally : Bool
        canPublishGlobally =
            has
                (if isEventContext then
                    PUBLISHEVENTSGLOBALLY

                 else
                    PUBLISHPOSTSGLOBALLY
                )
    in
    allVisibilities
        |> List.filter
            (\visibility ->
                case visibility of
                    SERVERPUBLIC ->
                        canPublishLocally || visibility == currentVisibility

                    GLOBALPUBLIC ->
                        canPublishGlobally || visibility == currentVisibility

                    _ ->
                        True
            )


{-| A post's star count -- `unauthenticatedStarCount` is a protobuf `int64`,
which `protoc-gen-elm` represents as `Protobuf.Types.Int64.Int64` rather than
plain `Int` since it may exceed JS's safe integer range in general; star
counts never will, so this is a safe, simple conversion for display.
-}
postStarCount : Post -> Int
postStarCount post =
    int64ToInt post.unauthenticatedStarCount


{-| Below this many characters of raw Markdown, a content preview (this
module's own `postCardView`, and `Components.Events.eventCard`, which reuses
it) shows the whole (short) message without fading its bottom edge -- the
fade exists to signal "there's more below the cutoff", which would be
misleading to show over a preview that isn't actually being truncated.
-}
contentPreviewFadeThreshold : Int
contentPreviewFadeThreshold =
    220
