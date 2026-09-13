module Components.Pages.PostsPage exposing
    ( FeedSource(..)
    , Model
    , Msg
    , exportButtonView
    , fromShared
    , init
    , searchTextChanged
    , showSyncDestinationsChanged
    , subscriptions
    , update
    , view
    )

{-| The shared guts of a "recent posts" page: fetching recent posts from every
enabled server and rendering them with fade in/out animations, plus a
search box + POST/REPLY context chooser (see `searchRowView`) that switches
the fetch to `TEXT_SEARCH` (debounced 311ms after typing stops) and persists
`search_text`/`context` as URL query params -- reused by `Pages.Home_` (which
adds its own "Recent Posts" heading and passes `author = Nothing`) and
`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts` (which pass the
already-resolved profile `User`, restricting the feed to that user's own
posts and adding this module's own "Posts | <name>" heading, via
`Components.Pages.UserProfilePage.nameHeader`), mirroring how
`Components.Pages.UserProfilePage` is reused by `Pages.UsernameOrCustomTab_` and
`Pages.User.UserId_` themselves.
-}

import Animation
import Browser.Navigation
import Components.Posts as Posts
import Components.Users exposing (usernameHref)
import Components.Users.ProfileHeading as ProfileHeading
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, h2, h3, input, option, p, select, span, text)
import Html.Attributes exposing (class, href, placeholder, selected, style, target, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Html.Keyed
import Http
import Json.Decode as Decode
import Ports
import Process
import Proto.Rellm exposing (Post, SyncDestination, User)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Conversions as Conversions
import Shared.CreateNewPanel as CreateNewPanel
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Mastodon as Mastodon
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import Shared.UserPreferences as UserPreferences
import Task
import Time
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.CustomNav as CustomNav
import UI.Flip
import Url.Builder



-- MODEL


type alias Model =
    { postsByServer : Dict String ServerFeed
    , postAnimations : Dict String PostAnimation
    , author : Maybe ( String, User )

    -- Set only by `Components.Pages.MastodonUserProfilePage`/`BlueskyUserProfilePage`'s own embedded
    -- copy, to a `MastodonAccountFeed`/`BlueskyAuthorFeed` naming the one profile being viewed --
    -- see `relevantFeedSources`'s own doc on why this can't just reuse `author` (which is typed to a
    -- real Rellm `Proto.Rellm.User`, and whose own author-scoping is deliberately Rellm-only, see
    -- `relevantServers`). `Nothing` for every other caller.
    , profileFeedSource : Maybe FeedSource

    -- `True` for embedded copies of this model (`Pages.Home_`,
    -- `Components.Pages.UserProfilePage`, passed via `init`'s own
    -- `embeddedPage` argument) -- gates `setBreadcrumbsRoot` off entirely
    -- (see its own doc): an embedding page already owns `Shared.Breadcrumbs`
    -- itself, so this copy asserting a root of its own on every `update`
    -- (including every animation tick, e.g. from `postAnimations`) would
    -- otherwise fight the real owner for it. Mirrors
    -- `Components.Pages.EventsPage.Model.embeddedPage` exactly.
    , embeddedPage : Bool
    , navKey : Browser.Navigation.Key
    , path : String
    , searchText : String
    , context : PostContext
    , searchGeneration : Int

    -- Which of `recentPostsTabsView`'s two tabs is active -- see `PostsTab`'s own doc.
    , tab : PostsTab

    -- The cutoff actually sent as `Components.Posts.fetchPosts`' own
    -- `publishedOrCreatedBefore` whenever `tab == PostsBeforeDate` (ignored
    -- entirely on `RecentPosts` -- see `refetchServers`'s own `fetchEffect`).
    -- Seeded at `init` from (in priority order) a `?published_before=` query
    -- param, then `Shared.UserPreferences.postsBefore` (the last cutoff the
    -- user actually typed in, persisted by `PublishedBeforeDebounceElapsed`
    -- -- a query param never writes it back, see that field's own doc), and
    -- only falls back to `Nothing` (resolved to "now" once `GotNow` fires,
    -- see its own doc) when neither is available -- mirrors
    -- `Components.Pages.EventsPage.Model.endsAfter`'s own "don't fetch
    -- before a real cutoff exists" doc, just seeded once rather than kept
    -- live.
    , publishedBefore : Maybe Time.Posix

    -- Debounces `PublishedBeforeInputChanged` (500ms) -- mirrors
    -- `Components.Pages.EventsPage.Model.endsAfterInputGeneration` exactly,
    -- just for this page's own date input.
    , publishedBeforeInputGeneration : Int

    -- Whether `postCardView` shows each card's `Posts.postSyncDestinationsView`
    -- -- defaults to `False` (`init`), set via `ShowSyncDestinationsChanged`.
    -- `Components.Pages.UserProfilePage`'s embedded copy keeps this in sync
    -- with its own `eventSyncDestinationsExpanded` section toggle; no other
    -- caller ever sets it, so it stays `False` (and this line doesn't render)
    -- everywhere else. Mirrors `Components.Pages.EventsPage.Model.showSyncDestinations`
    -- exactly -- Posts have no equivalent of `EventsPage`'s own `showSyncSources`,
    -- since there's no "Post Sync Source" concept.
    , showSyncDestinations : Bool

    -- Threaded straight into `Posts.postCard`'s own `availableSyncDestinations`
    -- param (see that function's own doc) -- set once at `init` (unlike
    -- `showSyncDestinations`, this only ever needs to change when the whole
    -- page gets re-inited anyway, since it comes from a resolved `User`, not
    -- a live UI toggle). `Nothing` for every caller except
    -- `Components.Pages.UserProfilePage`, which passes `Just user.syncDestinations`
    -- -- see `init`'s own doc. Mirrors `Components.Pages.EventsPage.Model.availableSyncDestinations`.
    , availableSyncDestinations : Maybe (List SyncDestination)

    -- `Submitting`/`SubmitFailed` push status per `postId ++ "|" ++
    -- destinationId` (many posts on screen at once) -- drives the
    -- `isPushing`/`pushError` closures `postCardView` builds for
    -- `Posts.postCard`. Mirrors `Components.Pages.EventsPage.Model.pushStatuses`
    -- exactly.
    , pushStatuses : Dict String SubmitStatus

    -- Whether the "Export" button's RSS/Atom-subscription-link popover (see
    -- `exportButtonView`) is currently open -- mirrors
    -- `Components.Pages.EventsPage.Model.exportPopoverOpen` exactly, just for RSS/Atom links
    -- instead of one ICS link.
    , exportPopoverOpen : Bool

    -- Which of the popover's two "Copy X Link" buttons (if either) most recently fired within
    -- the last 5s -- shows "Link Copied!" on that one specifically (unlike
    -- `Components.Pages.EventsPage.Model.copyLinkCopied`'s plain `Bool`, since there are two
    -- separate links/buttons here to disambiguate between). `copyLinkGeneration` mirrors that
    -- same debounce convention exactly -- see its own doc.
    , copyLinkCopied : Maybe ExportFeedKind
    , copyLinkGeneration : Int
    }


{-| Which feed format a `CopyLinkClicked`/the popover's own link `<a>` refers to -- RSS
(`GET /rss.xml`) or Atom (`GET /atom.xml`, see `backend/src/web/rss_subscription.rs`/
`atom_subscription.rs`).
-}
type ExportFeedKind
    = Rss
    | Atom


{-| Mirrors `Components.Pages.EventsPage.SubmitStatus`/`Pages.Event.PostId_.SubmitStatus`
exactly -- see `Model.pushStatuses`.
-}
type SubmitStatus
    = Submitting
    | SubmitFailed String


type Msg
    = GotFeedPosts String FeedResult
    | Poll
    | Animate Animation.Msg
    | RemovePost String
    | SharedMsg Shared.Msg
    | SearchTextChanged String
    | SearchDebounceElapsed Int
    | ContextChanged String
    | ClearSearchClicked
      -- Switches `model.tab` -- a no-op if already active. Mirrors
      -- `Components.Pages.EventsPage.TabChanged` in spirit: no shared
      -- layout/animation to slide between, just a different fetch cutoff, so
      -- this just updates `model.tab`/refetches/persists the URL directly --
      -- except switching to `PostsBeforeDate` for the very first time (no
      -- `model.publishedBefore` yet) instead seeds one via `GotNow` first.
      -- See `recentPostsTabsView`.
    | TabChanged PostsTab
      -- `Task.perform GotNow Time.now`'s result, fired only when
      -- `PostsBeforeDate` is selected with no `model.publishedBefore` yet
      -- (see `TabChanged`) -- seeds it with the current time (a sensible
      -- starting cutoff the user can then dial back) and fetches.
    | GotNow Time.Posix
      -- The `PostsBeforeDate` tab's `<input type="datetime-local">` firing --
      -- mirrors `Components.Pages.EventsPage.EndsAfterInputChanged` exactly,
      -- just against this page's own `publishedBefore`/`publishedBeforeInputGeneration`.
    | PublishedBeforeInputChanged String
      -- `PublishedBeforeInputChanged`'s debounce timer elapsing -- mirrors
      -- `Components.Pages.EventsPage.EndsAfterDebounceElapsed`'s own stale-
      -- generation guard, and (once settled) also persists
      -- `model.publishedBefore` as `Shared.UserPreferences.postsBefore`.
    | PublishedBeforeDebounceElapsed Int
      -- Sets `model.showSyncDestinations` -- driven by
      -- `Components.Pages.UserProfilePage`'s own "Sync Destinations"
      -- section-expanded toggle (see `Model.showSyncDestinations`'s own doc),
      -- not by anything in this page's own UI.
    | ShowSyncDestinationsChanged Bool
      -- The Push button on a card's `Posts.postCard`-rendered sync
      -- destination row (see `Model.availableSyncDestinations`'s own doc) --
      -- host/postId/syncDestinationId, keyed into `Model.pushStatuses` via
      -- `pushStatusKey`. Mirrors `Components.Pages.EventsPage.PushOccasionToDestination`
      -- exactly.
    | PushPostToDestination String String String
    | GotPushResult String String String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- Opens/closes the "Export" button's RSS/Atom-subscription-link popover (see
      -- `exportButtonView`) -- mirrors `Components.Pages.EventsPage.ExportClicked`/
      -- `ExportPopoverClosed` exactly.
    | ExportClicked
    | ExportPopoverClosed
      -- Copies `feedUrl kind`'s link to the clipboard via `Ports.copyToClipboard` and shows
      -- "Link Copied!" on that one button for 5s -- mirrors
      -- `Components.Pages.EventsPage.CopyLinkClicked`/`CopyLinkCopyTimeoutElapsed` exactly, just
      -- carrying which of the two links (`ExportFeedKind`) was copied.
    | CopyLinkClicked ExportFeedKind
    | CopyLinkCopyTimeoutElapsed Int


type ServerPosts
    = Loading
    | Loaded (List Post)
    | Failed


{-| `accountId` is the enabled account (if any) the posts were/are being
fetched with, so a later account enable/disable on the same server can be
detected as "the acting credential changed" and trigger a re-fetch.
-}
type alias ServerFeed =
    { status : ServerPosts
    , accountId : Maybe String
    }


{-| One source `postsByServer` can hold a feed for -- a real Rellm server (federating in the usual
way, `RellmServer`), or a Mastodon instance/Bluesky account translated client-side (see
`Shared.Federation.Mastodon`/`Bluesky`). Unifies what used to be two entirely separate
fetch-and-store paths (`postsByServer`/`GotServerPosts`/`fetchNewServers`/`refetchServers` vs.
`federatedPosts`/`GotFederatedPosts`/`fetchFederatedPosts`) into one, since both are ultimately
"fetch some posts for a host key, store them under that key, let `syncAnimations` render them" --
they just reach different APIs, with different capabilities, to do it. See `feedSourceKey`/
`feedSourceAccountId`/`fetchFeedSource` for where the three cases actually diverge.
-}
type FeedSource
    = RellmServer RellmServer
    | MastodonInstance String
    | BlueskyFeed BlueskyAccount
    | MastodonAccountFeed { instanceHost : String, accountId : String, username : String }
    | BlueskyAuthorFeed { handle : String }


{-| `postsByServer`'s key for a given `FeedSource` -- a real server's own `frontendHost`, or a
synthetic `"mastodon:"`/`"bluesky:"`-prefixed key that can never collide with one, mirroring
`Shared.Federation.Mastodon`/`Bluesky`'s own `Post.id` namespacing for the same reason.
`MastodonAccountFeed`/`BlueskyAuthorFeed` deliberately reuse the exact same `"mastodon:" ++
instanceHost`/`"bluesky:" ++ handle` shapes `MastodonInstance`/`BlueskyFeed` already use (rather than
some third, profile-specific prefix): the key doubles as every card's own `postServerHost` (see
`postCardView`), and clicking through to one of these posts individually needs to build an href
`Components.Users.parseFederatedUserId`/`Components.Posts.parseFederatedPostId` can actually parse
back -- both only ever look at the `"mastodon:"`/`"bluesky:"` prefix itself, so reusing it here is
what makes that round-trip work, not an accident.
-}
feedSourceKey : FeedSource -> String
feedSourceKey source =
    case source of
        RellmServer server ->
            server.frontendHost

        MastodonInstance host ->
            "mastodon:" ++ host

        BlueskyFeed account ->
            "bluesky:" ++ account.handle

        MastodonAccountFeed ref ->
            "mastodon:" ++ ref.instanceHost

        BlueskyAuthorFeed ref ->
            "bluesky:" ++ ref.handle


{-| The acting credential a `FeedSource`'s feed is fetched with, if any -- a real server's enabled
account, or always `Nothing` for Mastodon/Bluesky, since neither is ever refetched on a credential
change the way a Rellm account is (browsing/reading Mastodon needs no sign-in at all; a Bluesky
account's token doesn't change without a full reconnect, which itself removes and re-adds the
account under a new key). `Nothing == Nothing` is exactly what makes `fetchNewFeeds` treat an
already-fetched federated source as unchanged forever -- except a _newly_ added instance/account
(not yet a key in `postsByServer` at all) now gets picked up live by the same `Poll`/`SharedMsg`
events real servers already use, rather than waiting for a fresh visit to this page the way the old,
separate `fetchFederatedPosts` (fired once, from `init`, only) did.
-}
feedSourceAccountId : Shared.Model -> FeedSource -> Maybe String
feedSourceAccountId shared source =
    case source of
        RellmServer server ->
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost
                |> Maybe.map RellmAccounts.rellmAccountId

        MastodonInstance _ ->
            Nothing

        BlueskyFeed _ ->
            Nothing

        MastodonAccountFeed _ ->
            Nothing

        BlueskyAuthorFeed _ ->
            Nothing


{-| One `FeedSource`'s fetch settling, normalized across the real-server (`Grpc.Error`/
`GetPostsResponse`) and Mastodon/Bluesky (`Http.Error`/plain `List Post`) shapes -- neither error
type's actual content is used anywhere once a fetch fails (see `GotFeedPosts`'s `FeedFailed`
branch), so there's nothing lost by discarding the distinction.
-}
type FeedResult
    = FeedLoaded (List Post) (Maybe AccountsPanel.Msg)
    | FeedFailed (Maybe AccountsPanel.Msg)


fromServerResult : Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetPostsResponse ) -> FeedResult
fromServerResult result =
    case result of
        Ok ( maybeAccountsPanelMsg, response ) ->
            FeedLoaded response.posts maybeAccountsPanelMsg

        Err _ ->
            FeedFailed Nothing


fromFederatedResult : Result Http.Error (List Post) -> FeedResult
fromFederatedResult result =
    case result of
        Ok posts ->
            FeedLoaded posts Nothing

        Err _ ->
            FeedFailed Nothing


{-| `BlueskyFeed`'s own `FeedResult` conversion -- unlike `fromFederatedResult`, this needs `account`
(the credential the request was fired with) alongside the raw `Result`, since
`BlueskyAccounts.performWithBlueskyAccount` may have silently rotated its tokens (a successful
refresh-and-retry, see that function's own doc) or exhausted its retry entirely (a `needsReauth`-worthy
failure, see `BlueskyAccounts.isReauthError`) -- either way something needs to reach
`Shared.AccountsPanel`'s own persisted `blueskyAccounts`, which this page has no direct write access
to. Piggybacks on the same `Maybe AccountsPanel.Msg` channel `fromServerResult` already uses for a
Rellm server's own token refresh, so `GotFeedPosts`'s handling doesn't need a federated-specific case.
-}
fromBlueskyResult : BlueskyAccount -> Result Http.Error ( BlueskyAccount, List Post ) -> FeedResult
fromBlueskyResult account result =
    case result of
        Ok ( refreshedAccount, posts ) ->
            FeedLoaded posts
                (if refreshedAccount.accessToken == account.accessToken then
                    Nothing

                 else
                    Just (AccountsPanel.BlueskyAccountRefreshed refreshedAccount)
                )

        Err err ->
            FeedFailed
                (if BlueskyAccounts.isReauthError err then
                    Just (AccountsPanel.MarkBlueskyAccountNeedsReauth account.handle)

                 else
                    Nothing
                )


{-| A post's fade in/out state, keyed in `postAnimations` by `postAnimationKey`
so it survives independently of `postsByServer` -- see that dict's own doc
comment for why: a server being disabled (or re-fetched under a different
account) drops/replaces its posts in `postsByServer` immediately, but a
`removing` `flip` entry here keeps rendering its last-known `post`/`host`
until its fade-out finishes, instead of the post just vanishing. See
`UI.Flip` for what `flip` itself drives.
-}
type alias PostAnimation =
    { host : String
    , post : Post
    , flip : UI.Flip.State Msg
    }


{-| Which of `recentPostsTabsView`'s two tabs is active -- `RecentPosts` (the
default) is this page's original, unfiltered-by-time feed; `PostsBeforeDate`
filters by a fixed, user-picked `model.publishedBefore` cutoff, sent as
`GetPostsRequest.published_or_created_before` (see
`backend/src/rpcs/posts/get_posts.rs`) -- editable via its own
`<input type="datetime-local">`. Persisted to the URL as a `published_before`
query param (see `pushUrl`) -- its mere presence/absence on load is what
`init` uses to decide which tab to start on, mirroring
`Components.Pages.EventsPage.EventsTab`/`?ends_after=` exactly. Only ever
shown (via `recentPostsTabsView`) on the standalone, unfiltered Posts page
(`model.author == Nothing`, `not model.embeddedPage`) -- see that view's own
doc for why.
-}
type PostsTab
    = RecentPosts
    | PostsBeforeDate


{-| `author`, if given, restricts the feed to that user's own posts (see
`Components.PostCard.fetchRecentPosts`) and adds a "Posts | <name>"
heading (see `view`) -- `Pages.Home_` passes `Nothing`,
`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts` pass their
already-resolved profile `User` paired with the host it was resolved from
(`Components.Users.Resolver`'s own `targetHost`, resolved before ever calling
this, so this module never needs to fetch the `User` itself -- it only needs
the host alongside it to look up that server's `RellmServer`/signed-in
`Account` for `authorHeadingView`'s avatar).

`navKey`/`path`, from the calling page's own `Request`, are what let
`searchRowView`'s search box/context chooser and `recentPostsTabsView`'s date
input persist `search_text`/`context`/`published_before` as URL query params
(see `pushUrl`) without this module needing to know which page-specific
`Gen.Params.*` type that `Request` is actually parameterized over -- every
caller's `Request.key`/`Request.url.path` fit this regardless. `query`, that
same `Request`'s already-parsed `.query`, seeds `searchText`/`context`/`tab`/
`publishedBefore` back out of the URL on load, so a shared/reloaded link
reproduces the same search/cutoff.

`embeddedPage` is `True` only for `Pages.Home_`'s and
`Components.Pages.UserProfilePage`'s own embedded copies -- see
`Model.embeddedPage`'s own doc.

`availableSyncDestinations` seeds `Model.availableSyncDestinations` directly -- `Nothing` for
every caller except `Components.Pages.UserProfilePage`, which passes `Just user.syncDestinations`.
Mirrors `Components.Pages.EventsPage.init`'s own trailing param exactly.

`profileFeedSource` seeds `Model.profileFeedSource` directly -- `Nothing` for every caller except
`Components.Pages.MastodonUserProfilePage`/`BlueskyUserProfilePage`, which pass `Just` a
`MastodonAccountFeed`/`BlueskyAuthorFeed` naming the one profile being viewed. See that field's own
doc for why this couldn't just reuse `author` instead.

-}
init : Shared.Model -> Maybe ( String, User ) -> Browser.Navigation.Key -> String -> Dict String String -> Bool -> Maybe (List SyncDestination) -> Maybe FeedSource -> ( Model, Effect Msg )
init shared author navKey path query embeddedPage availableSyncDestinations profileFeedSource =
    let
        ( tab, publishedBefore ) =
            case Dict.get "published_before" query |> Maybe.andThen Conversions.posixFromIsoUtcString of
                Just cutoff ->
                    ( PostsBeforeDate, Just cutoff )

                Nothing ->
                    ( RecentPosts, shared.userPreferences.postsBefore )

        ( fetchedModel, fetchEffect ) =
            fetchNewFeeds shared
                { postsByServer = Dict.empty
                , postAnimations = Dict.empty
                , author = author
                , profileFeedSource = profileFeedSource
                , embeddedPage = embeddedPage
                , navKey = navKey
                , path = path
                , searchText = Dict.get "search_text" query |> Maybe.withDefault ""
                , context = Dict.get "context" query |> Maybe.andThen postContextFromParam |> Maybe.withDefault POST
                , searchGeneration = 0
                , tab = tab
                , publishedBefore = publishedBefore
                , publishedBeforeInputGeneration = 0
                , showSyncDestinations = False
                , availableSyncDestinations = availableSyncDestinations
                , pushStatuses = Dict.empty
                , exportPopoverOpen = False
                , copyLinkCopied = Nothing
                , copyLinkGeneration = 0
                }
    in
    -- Closes any open panel (Accounts, Starred, etc.) unconditionally on
    -- load -- `setBreadcrumbsRoot` below only does this as a side effect of
    -- actually changing `shared.breadcrumbs.root` (see `Shared.update`'s
    -- `SetRoot` branch), which is a no-op for two pages that share a root,
    -- e.g. landing here right after `/people` while both are still
    -- `FromServerHost mainFrontendHost`. Mirrors
    -- `Components.Pages.UserProfilePage.init`'s own unconditional close.
    --
    -- Also unconditionally kicks off `Task.perform GotNow Time.now` (even
    -- while `tab == RecentPosts`, and even when a `?published_before=` query
    -- param or `Shared.UserPreferences.postsBefore` already resolved one) so
    -- `model.publishedBefore` is seeded with the page's own load time before
    -- the user ever switches to `PostsBeforeDate` -- otherwise
    -- `recentPostsTabsView`'s date input would flash its `Time.millisToPosix
    -- 0` fallback (the Unix epoch, so 1969/1970 depending on the viewer's
    -- own time zone) for the brief window between that switch and `GotNow`
    -- resolving. `GotNow`'s own `model.publishedBefore == Nothing` guard is
    -- what makes this a no-op once a query-param/preference cutoff (or a
    -- still-in-flight earlier `GotNow`) has already claimed it.
    ( fetchedModel
    , Effect.batch
        [ fetchEffect
        , Effect.fromShared Shared.CloseAllPanels
        , setBreadcrumbsRoot shared fetchedModel
        , Task.perform GotNow Time.now |> Effect.fromCmd
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 30000 (\_ -> Poll)
        , UI.Flip.subscription Animate (List.map .flip (Dict.values model.postAnimations))
        ]



-- UPDATE


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
(see `Main.notifyPageOfSharedMsg`) into `update`'s `SharedMsg` branch, without
exposing the `SharedMsg` constructor itself (and thus every other constructor
of this otherwise-opaque `Msg`) outside this module.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


{-| Lets a sibling page (`Pages.Home_`, keeping its embedded `EventsPage`'s search box in sync
with this module's own `model.searchText` behind the scenes -- see that module's own
`searchTextChanged` and `Pages.Home_.update`'s cross-sync) feed a search-text change in from
outside exactly as if the user had typed it into this module's own (on `Pages.Home_`, hidden --
see `view`'s `showSearchRow`) search box -- same `SearchTextChanged`/`SearchDebounceElapsed`
round-trip, same independent debounce timer, without exposing the `SearchTextChanged` constructor
itself (and thus every other constructor of this otherwise-opaque `Msg`) outside this module.
-}
searchTextChanged : String -> Msg
searchTextChanged =
    SearchTextChanged


{-| Lets `Components.Pages.UserProfilePage` keep this page's `showSyncDestinations` in sync with
its own "Sync Destinations" section-expanded toggle, the same way `searchTextChanged` lets
`Pages.Home_` feed in a search-text change -- without exposing the `ShowSyncDestinationsChanged`
constructor itself (and thus every other constructor of this otherwise-opaque `Msg`) outside this
module. Mirrors `Components.Pages.EventsPage.showSyncDestinationsChanged` exactly.
-}
showSyncDestinationsChanged : Bool -> Msg
showSyncDestinationsChanged =
    ShowSyncDestinationsChanged


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            updateInner shared msg model
    in
    ( newModel, Effect.batch [ effect, setBreadcrumbsRoot shared newModel ] )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        GotFeedPosts host (FeedLoaded rawPosts maybeAccountsPanelMsg) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none

                -- Posts already featured via a server's own custom nav tab (see
                -- `customNavPostIds`) are dropped from that server's generic feed -- they've
                -- already got their own dedicated tab/url (`UI.CustomNav`/
                -- `Pages.UsernameOrCustomTab_`), so showing them here too would just be clutter.
                -- `customNavPostIds host` only ever looks at `host`'s own `customTabs` -- a
                -- `CustomNavigationTab.post_id` is always assumed to name a Post on that server (see
                -- `UI.CustomNav.CustomTabTarget`'s own doc), so it'd be a coincidence, not a real
                -- match, for some other federated server's (or Mastodon/Bluesky's) own post to share
                -- that id; a synthetic Mastodon/Bluesky `host` simply has no `customTabs` at all, so
                -- this is naturally a no-op filter for those. Skipped entirely when
                -- `Shared.debugShowCustomNavPosts` is set, so DebugTab's "Show Posts linked to
                -- Custom Tabs" toggle can surface them for inspection.
                posts : List Post
                posts =
                    if shared.accounts.debugTab.showCustomNavPosts then
                        rawPosts

                    else
                        rawPosts |> List.filter (\post -> not (Set.member post.id (customNavPostIds shared host)))
            in
            ( { model
                | postsByServer =
                    Dict.update host
                        (Maybe.map (\feed -> { feed | status = Loaded posts }))
                        model.postsByServer
              }
                |> syncAnimations
            , accountEffect
            )

        GotFeedPosts host (FeedFailed maybeAccountsPanelMsg) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none
            in
            ( { model
                | postsByServer =
                    Dict.update host (Maybe.map (\feed -> { feed | status = Failed })) model.postsByServer
              }
                |> syncAnimations
            , accountEffect
            )

        Poll ->
            fetchNewFeeds shared model

        Animate animMsg ->
            let
                step : String -> PostAnimation -> ( Dict String PostAnimation, List (Cmd Msg) ) -> ( Dict String PostAnimation, List (Cmd Msg) )
                step key anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert key { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.postAnimations
            in
            ( { model | postAnimations = newAnimations }, Effect.batch (List.map Effect.fromCmd cmds) )

        RemovePost key ->
            ( { model | postAnimations = Dict.remove key model.postAnimations }, Effect.none )

        SharedMsg subMsg ->
            let
                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        Shared.AccountsPanelMsg _ ->
                            fetchNewFeeds shared model

                        -- The Delete button on a card's sync destination row
                        -- (`Shared.RequestDelete`/`Shared.ConfirmPostSyncDestinationDelete`, see
                        -- `postCardView`'s own `onDelete`) resolving -- mirrors
                        -- `Components.Pages.EventsPage`'s identical
                        -- `Shared.GotOccasionSyncDestinationDeleteResult` handling (re-scoped
                        -- refetch of just `host`'s server), since a successful un-sync changes
                        -- `post.syncDestinations` behind this already-fetched copy's back the same way.
                        Shared.GotPostSyncDestinationDeleteResult host (Ok _) ->
                            case RellmServers.rellmServerForHost shared.accounts.servers host of
                                Just server ->
                                    refetchFeeds shared model [ RellmServer server ]

                                Nothing ->
                                    ( model, Effect.none )

                        Shared.CreateNewPanelMsg (CreateNewPanel.GotSaveResult (Ok ( _, createdItem ))) ->
                            applyCreatedItem shared createdItem model

                        _ ->
                            ( model, Effect.none )
            in
            ( fetchedModel, Effect.batch [ Effect.fromShared subMsg, fetchEffect ] )

        SearchTextChanged text ->
            let
                generation : Int
                generation =
                    model.searchGeneration + 1
            in
            ( { model | searchText = text, searchGeneration = generation }
            , Process.sleep 311
                |> Task.perform (\_ -> SearchDebounceElapsed generation)
                |> Effect.fromCmd
            )

        SearchDebounceElapsed generation ->
            if generation == model.searchGeneration then
                applySearchChange shared model

            else
                -- A later edit (or ClearSearchClicked/ContextChanged) already
                -- bumped searchGeneration past this timer's -- it's stale, ignore it.
                ( model, Effect.none )

        ContextChanged param ->
            case postContextFromParam param of
                Just newContext ->
                    applySearchChange shared { model | context = newContext, searchGeneration = model.searchGeneration + 1 }

                Nothing ->
                    ( model, Effect.none )

        ClearSearchClicked ->
            applySearchChange shared { model | searchText = "", searchGeneration = model.searchGeneration + 1 }

        TabChanged RecentPosts ->
            if model.tab == RecentPosts then
                ( model, Effect.none )

            else
                let
                    ( refetchedModel, refetchEffect ) =
                        refetchFeeds shared { model | tab = RecentPosts } (List.map RellmServer (relevantServers shared model))
                in
                ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )

        TabChanged PostsBeforeDate ->
            if model.tab == PostsBeforeDate then
                ( model, Effect.none )

            else
                case model.publishedBefore of
                    Just _ ->
                        let
                            ( refetchedModel, refetchEffect ) =
                                refetchFeeds shared { model | tab = PostsBeforeDate } (List.map RellmServer (relevantServers shared model))
                        in
                        ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )

                    Nothing ->
                        ( { model | tab = PostsBeforeDate }, Task.perform GotNow Time.now |> Effect.fromCmd )

        GotNow now ->
            case model.publishedBefore of
                Just _ ->
                    -- Already seeded (a `?published_before=` query param on
                    -- load, or an earlier `GotNow`) -- this one's redundant.
                    ( model, Effect.none )

                Nothing ->
                    let
                        newModel : Model
                        newModel =
                            { model | publishedBefore = Just now }
                    in
                    if newModel.tab == PostsBeforeDate then
                        let
                            ( refetchedModel, refetchEffect ) =
                                refetchFeeds shared newModel (List.map RellmServer (relevantServers shared newModel))
                        in
                        ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )

                    else
                        -- `RecentPosts` doesn't use `publishedBefore` at all
                        -- (see `fetchFeedSource`'s own `cutoff`) -- just seed
                        -- it quietly so it's ready the moment the user does
                        -- switch tabs, no fetch/URL change needed yet.
                        ( newModel, Effect.none )

        PublishedBeforeInputChanged raw ->
            case SharedTime.posixFromDateTimeLocalInput shared.time.browserTimeZone.zone raw of
                Nothing ->
                    ( model, Effect.none )

                Just newPublishedBefore ->
                    let
                        generation : Int
                        generation =
                            model.publishedBeforeInputGeneration + 1
                    in
                    ( { model | tab = PostsBeforeDate, publishedBefore = Just newPublishedBefore, publishedBeforeInputGeneration = generation }
                    , Process.sleep 500
                        |> Task.perform (\_ -> PublishedBeforeDebounceElapsed generation)
                        |> Effect.fromCmd
                    )

        PublishedBeforeDebounceElapsed generation ->
            if generation == model.publishedBeforeInputGeneration then
                let
                    ( refetchedModel, refetchEffect ) =
                        refetchFeeds shared model (List.map RellmServer (relevantServers shared model))
                in
                ( refetchedModel
                , Effect.batch
                    [ refetchEffect
                    , pushUrl refetchedModel
                    , Effect.fromShared (Shared.UserPreferencesMsg (UserPreferences.SetPostsBefore model.publishedBefore))
                    ]
                )

            else
                -- A later edit already bumped `publishedBeforeInputGeneration`
                -- past this timer's -- it's stale, ignore it.
                ( model, Effect.none )

        ShowSyncDestinationsChanged showSyncDestinations ->
            ( { model | showSyncDestinations = showSyncDestinations }, Effect.none )

        PushPostToDestination host postId syncDestinationId ->
            let
                key : String
                key =
                    pushStatusKey postId syncDestinationId

                maybeAccountServer : ( Maybe String, String )
                maybeAccountServer =
                    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId, host )
            in
            ( { model | pushStatuses = Dict.insert key Submitting model.pushStatuses }
            , Posts.syncPost shared.accounts maybeAccountServer postId syncDestinationId
                |> Task.attempt (GotPushResult host postId syncDestinationId)
                |> Effect.fromCmd
            )

        GotPushResult host postId syncDestinationId result ->
            let
                key : String
                key =
                    pushStatusKey postId syncDestinationId

                clearedModel : Model
                clearedModel =
                    { model | pushStatuses = Dict.remove key model.pushStatuses }
            in
            case result of
                Ok ( maybeAccountsPanelMsg, _ ) ->
                    let
                        ( refetchedModel, refetchEffect ) =
                            case RellmServers.rellmServerForHost shared.accounts.servers host of
                                Just server ->
                                    refetchFeeds shared clearedModel [ RellmServer server ]

                                Nothing ->
                                    ( clearedModel, Effect.none )
                    in
                    ( refetchedModel
                    , Effect.batch
                        [ refetchEffect
                        , maybeAccountsPanelMsg
                            |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                            |> Maybe.withDefault Effect.none
                        ]
                    )

                Err err ->
                    ( { clearedModel | pushStatuses = Dict.insert key (SubmitFailed (AccountsPanel.grpcErrorToString err)) clearedModel.pushStatuses }
                    , Effect.none
                    )

        ExportClicked ->
            ( { model | exportPopoverOpen = not model.exportPopoverOpen }, Effect.none )

        ExportPopoverClosed ->
            ( { model | exportPopoverOpen = False }, Effect.none )

        CopyLinkClicked kind ->
            let
                generation : Int
                generation =
                    model.copyLinkGeneration + 1
            in
            ( { model | copyLinkCopied = Just kind, copyLinkGeneration = generation }
            , Effect.batch
                [ Ports.copyToClipboard (feedUrl shared model kind) |> Effect.fromCmd
                , Process.sleep 5000
                    |> Task.perform (\_ -> CopyLinkCopyTimeoutElapsed generation)
                    |> Effect.fromCmd
                ]
            )

        CopyLinkCopyTimeoutElapsed generation ->
            if generation == model.copyLinkGeneration then
                ( { model | copyLinkCopied = Nothing }, Effect.none )

            else
                -- A later `CopyLinkClicked` already bumped `copyLinkGeneration` past this
                -- timer's -- it's stale, ignore it.
                ( model, Effect.none )


pushStatusKey : String -> String -> String
pushStatusKey postId syncDestinationId =
    postId ++ "|" ++ syncDestinationId


{-| The servers this page should ever fetch from: every enabled server for an
unfiltered feed (`model.author == Nothing`, e.g. `Pages.Home_`), or, once
`author` restricts the feed to one user, _only_ that user's own resolved
host -- looked up via `RellmServers.rellmServerForHost` (not `enabledServers`),
since a user profile can be resolved, and its posts fetched anonymously,
from a known server the viewer hasn't toggled "enabled" (or isn't signed
into at all) -- see `Components.Users.Resolver.fetchTask`, which resolves
`author` itself the same way. Without this restriction, both plain listing
and (especially) `TEXT_SEARCH` would fan out to every other enabled server
too, e.g. showing `jon@oakcitysocial.com`'s posts on `jon@jonline.io`'s
own posts page.
-}
relevantServers : Shared.Model -> Model -> List RellmServer
relevantServers shared model =
    case model.author of
        Just ( host, _ ) ->
            RellmServers.rellmServerForHost shared.accounts.servers host
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        Nothing ->
            AccountsPanel.enabledServers shared.accounts


{-| Every Post id `frontendHost`'s own `ServerConfiguration.customTabs` points a `TargetPost` tab
at, plus its `home` override's own Post id if it's using one, and every one of its `pinnedPostIds`
(`UI.CustomNav.homeConfig`) -- what `GotFeedPosts` excludes from `frontendHost`'s own feed (see
its own doc), so a Post already featured via its own custom nav tab/url (or as the custom Home page,
or pinned to its top) doesn't also clutter the generic listing. Applies to every known server, not
just `mainFrontendHost` -- each federated server's custom nav tabs only ever point at that same
server's own posts (see `UI.CustomNav.CustomTabTarget`'s own doc), so this is looked up
per-`frontendHost` rather than once for `mainFrontendHost`.
-}
customNavPostIds : Shared.Model -> String -> Set String
customNavPostIds shared frontendHost =
    let
        maybeCustomTabs : Maybe Proto.Rellm.CustomNavigationTabSet
        maybeCustomTabs =
            RellmServers.rellmServerForHost shared.accounts.servers frontendHost
                |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customTabs)

        tabPostIds : List String
        tabPostIds =
            maybeCustomTabs
                |> Maybe.map (\customTabs -> CustomNav.effectiveTabs (Just customTabs))
                |> Maybe.withDefault []
                |> List.filterMap
                    (\tab ->
                        case tab.target of
                            CustomNav.TargetPost postId ->
                                Just postId

                            _ ->
                                Nothing
                    )

        home : CustomNav.HomePageConfig
        home =
            CustomNav.homeConfig maybeCustomTabs

        homePostIds : List String
        homePostIds =
            case home.target of
                CustomNav.TargetPost postId ->
                    postId :: home.pinnedPostIds

                _ ->
                    home.pinnedPostIds
    in
    homePostIds ++ tabPostIds |> Set.fromList


{-| Every `FeedSource` this page should ever fetch from -- `relevantServers`' real Rellm servers
(unconditionally), plus every Mastodon instance being browsed/connected and every connected Bluesky
account, but only while the feed isn't scoped to one particular author (`model.author == Nothing`),
since neither Mastodon nor Bluesky supports the author-scoping a real `GetPosts` request does
(`fetchFeedSource` doesn't even attempt to send that for a `MastodonInstance`/`BlueskyFeed`), so
showing them on someone's profile page would be misleading -- they'd read as that person's own posts.

Deliberately _not_ also gated on `model.embeddedPage`: that's `True` for both
`Components.Pages.UserProfilePage`'s embedded copy (already excluded above, since it's author-scoped)
and `Pages.Home_`'s "Recent Posts" widget (`model.author == Nothing`, exactly like the standalone
Posts page) -- Home's embedded copy has just as much claim to showing federated content as the
standalone page does, so there's nothing about `embeddedPage` alone that should exclude it. Text
search/`PostsBeforeDate` aren't a factor either way, on Home or the standalone page: a federated fetch
is never re-triggered by `applySearchChange`/`TabChanged` (see `refetchFeeds`'s own doc), so an
already-fetched federated post simply keeps showing, unfiltered by whatever search text is active --
an accepted first-pass limitation on the standalone page already, not a new one introduced here.

`model.profileFeedSource`, when set, overrides everything above outright -- `Components.Pages.MastodonUserProfilePage`/
`BlueskyUserProfilePage` embed this module purely to show one specific federated profile's own posts
(a `MastodonAccountFeed`/`BlueskyAuthorFeed`, see `Model.profileFeedSource`'s own doc), which has no
Rellm server of its own to resolve via `relevantServers` at all -- unlike `model.author`'s Rellm-only
author-scoping, there's exactly one source to ever fetch here, not "every relevant server plus zero
federated ones."

-}
relevantFeedSources : Shared.Model -> Model -> List FeedSource
relevantFeedSources shared model =
    case model.profileFeedSource of
        Just source ->
            [ source ]

        Nothing ->
            List.map RellmServer (relevantServers shared model)
                ++ (if model.author /= Nothing then
                        []

                    else
                        List.map MastodonInstance (mastodonHostsToFetch shared)
                            ++ List.map BlueskyFeed (List.filter .enabled shared.accounts.blueskyAccounts)
                   )


{-| Every Mastodon instance host worth fetching -- both accounts connected via OAuth
(`mastodonAccounts`, which have no enable/disable flag of their own -- see that field's own doc) and
instances just being browsed anonymously and currently enabled (`browsedMastodonInstances`, see
`BrowsedMastodonInstance`'s own doc on what disabling one does here) -- deduplicated,
since `Mastodon.fetchPosts` hits the exact same unauthenticated public-timeline endpoint either way
(see that function's own doc: it never actually uses a `MastodonAccount`'s `accessToken`) -- there's
nothing a connected account's fetch gets that a browsed one doesn't, so fetching the same host twice
would just be a wasted request.
-}
mastodonHostsToFetch : Shared.Model -> List String
mastodonHostsToFetch shared =
    (List.map .instanceHost shared.accounts.mastodonAccounts
        ++ (shared.accounts.browsedMastodonInstances |> List.filter .enabled |> List.map .host)
    )
        |> Set.fromList
        |> Set.toList


{-| Actually fires one `FeedSource`'s fetch -- a real `GetPosts` RPC (author-scoped, search/context/
cutoff-aware) for a `RellmServer`, or an unauthenticated/self-authenticated plain `Task.attempt`
against Mastodon's/Bluesky's own REST API for the other two, translated via
`Shared.Federation.Mastodon.fetchPosts`/`Shared.Federation.Bluesky.fetchPosts`. `BlueskyFeed` is the
one partial exception: a non-blank `model.searchText` switches it to `Bluesky.searchPosts` instead
(Bluesky's own real, network-wide search endpoint) -- the closest either federated source gets to a
real `GetPosts` request's own `TEXTSEARCH` mode. `MastodonInstance` has no search equivalent wired up
at all, so its fetch ignores `model.searchText` entirely. Every case funnels its result through the
same `GotFeedPosts` `Msg` regardless -- see `fromServerResult`/`fromFederatedResult`.
-}
fetchFeedSource : Shared.Model -> Model -> FeedSource -> Effect Msg
fetchFeedSource shared model source =
    case source of
        RellmServer server ->
            let
                cutoff : Maybe Time.Posix
                cutoff =
                    if model.tab == PostsBeforeDate then
                        model.publishedBefore

                    else
                        Nothing
            in
            Posts.fetchPosts
                shared.accounts
                ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost |> Maybe.map .userId
                , server.frontendHost
                )
                (model.author |> Maybe.map (Tuple.second >> .id))
                model.searchText
                model.context
                cutoff
                |> Task.attempt (fromServerResult >> GotFeedPosts server.frontendHost)
                |> Effect.fromCmd

        MastodonInstance host ->
            Mastodon.fetchPosts host
                |> Task.attempt (fromFederatedResult >> GotFeedPosts (feedSourceKey source))
                |> Effect.fromCmd

        BlueskyFeed account ->
            let
                trimmedSearch : String
                trimmedSearch =
                    String.trim model.searchText

                request : String -> Task.Task Http.Error (List Post)
                request accessToken =
                    if String.isEmpty trimmedSearch then
                        Bluesky.fetchPosts accessToken

                    else
                        Bluesky.searchPosts accessToken trimmedSearch
            in
            BlueskyAccounts.performWithBlueskyAccount account request
                |> Task.attempt (fromBlueskyResult account >> GotFeedPosts (feedSourceKey source))
                |> Effect.fromCmd

        MastodonAccountFeed ref ->
            Mastodon.fetchAccountStatuses ref.instanceHost ref.accountId
                |> Task.attempt (fromFederatedResult >> GotFeedPosts (feedSourceKey source))
                |> Effect.fromCmd

        BlueskyAuthorFeed ref ->
            case shared.accounts.blueskyAccounts of
                viewerAccount :: _ ->
                    BlueskyAccounts.performWithBlueskyAccount viewerAccount (\accessToken -> Bluesky.fetchAuthorFeed accessToken ref.handle)
                        |> Task.attempt (fromBlueskyResult viewerAccount >> GotFeedPosts (feedSourceKey source))
                        |> Effect.fromCmd

                [] ->
                    -- No connected Bluesky account to authenticate this request with at all (AT
                    -- Proto has no anonymous access -- see `Shared.Federation.Bluesky`'s own doc) --
                    -- `Components.Pages.BlueskyUserProfilePage.init` already refuses to even mount
                    -- this `FeedSource` in that case (see its own doc), so this is unreachable in
                    -- practice; `Effect.none` rather than a synthetic failure since there's no
                    -- `BlueskyAccount` on hand for `fromBlueskyResult` to attribute one to.
                    Effect.none


{-| Fetches `sourcesToFetch` using the current `model.searchText`/`model.context` (for a `RellmServer`,
full author-scoped/search/context/cutoff support; for a `BlueskyFeed`, just `model.searchText`, see
`fetchFeedSource`'s own doc; meaningless to a `MastodonInstance`, which has no search of its own),
and drops any already-fetched source that's no longer `relevantFeedSources` -- shared by
`fetchNewFeeds` (which only passes the sources that actually need it, see its own doc comment) and
`applySearchChange` (which always passes every relevant server _and_ Bluesky account, since a changed
search must re-fetch everything regardless of whether that source's acting account also happens to
have changed -- `MastodonInstance` sources are deliberately never included there, since they have no
server-side search at all, so re-fetching one on every keystroke would just be a wasted,
unfiltered-anyway request).

A source already `Loaded` under the _same_ acting account (see `feedSourceAccountId`) keeps showing
its last-known posts (`status` left untouched) while the re-fetch is in flight, rather than being
reset to `Loading` first -- `Loading` isn't rendered as its own state anywhere in this module, so the
only thing resetting it did was drop that source out of `syncAnimations`' `currentPosts`, which reads
as every one of its posts fading out and back in a moment later, even though `applySearchChange`'s
response usually still contains most of the same posts. See
`Components.Pages.EventsPage.refetchServers`'s own doc for where this was first diagnosed (a periodic
full-list flicker there) and ported from. A genuinely new source, or a `RellmServer` whose acting
account just changed (sign-in/out), still resets to `Loading` -- its previous posts (fetched under a
different or no account) are stale/invalid, not just "not yet refreshed," so they should disappear
rather than linger.

A no-op (nothing touched, no fetch fired) while `model.tab == PostsBeforeDate` and
`model.publishedBefore` is still `Nothing` -- mirrors `Components.Pages.EventsPage.refetchServers`'s
own guard on `model.endsAfter`: fetching with no real cutoff yet in hand would ask for `RecentPosts`'
full feed for the brief instant before `GotNow` resolves one, rather than just waiting.

-}
refetchFeeds : Shared.Model -> Model -> List FeedSource -> ( Model, Effect Msg )
refetchFeeds shared model sourcesToFetch =
    if model.tab == PostsBeforeDate && model.publishedBefore == Nothing then
        ( model, Effect.none )

    else
        let
            keptKeys : List String
            keptKeys =
                relevantFeedSources shared model |> List.map feedSourceKey

            prunedPostsByServer : Dict String ServerFeed
            prunedPostsByServer =
                Dict.filter (\host _ -> List.member host keptKeys) model.postsByServer

            markSource : FeedSource -> Dict String ServerFeed -> Dict String ServerFeed
            markSource source dict =
                let
                    key : String
                    key =
                        feedSourceKey source

                    accountId : Maybe String
                    accountId =
                        feedSourceAccountId shared source

                    statusIfSameAccount : Maybe ServerPosts
                    statusIfSameAccount =
                        Dict.get key dict
                            |> Maybe.andThen
                                (\feed ->
                                    if feed.accountId == accountId then
                                        Just feed.status

                                    else
                                        Nothing
                                )
                in
                Dict.insert key
                    { status = Maybe.withDefault Loading statusIfSameAccount, accountId = accountId }
                    dict
        in
        ( { model
            | postsByServer =
                List.foldl markSource prunedPostsByServer sourcesToFetch
          }
        , Effect.batch (List.map (fetchFeedSource shared model) sourcesToFetch)
        )
            |> Tuple.mapFirst syncAnimations


{-| Drops posts for sources that are no longer relevant (so disabling a server, or removing a
browsed Mastodon instance/connected Bluesky account, hides its posts entirely), and re-fetches a
`RellmServer` whose acting account (the first enabled account signed into it, or anonymous) has
changed since the last fetch -- covering both disabling an account (falls back to anonymous) and
enabling a different one. A `MastodonInstance`/`BlueskyFeed` never has an "acting account" that can
change this way (see `feedSourceAccountId`), so this only ever re-fetches one of those the first time
it shows up as a key that isn't in `model.postsByServer` yet -- i.e. once, right after it's
added/connected, live while this page is already open, rather than waiting for a fresh visit.
Already-fetched-with-the-same-account sources are cheap to skip, so this is safe to call as often as
it likes.

This is event-driven -- any `AccountsPanel` message passing through `update`'s `SharedMsg` branch
triggers a call, since that covers server/account add/remove/enable/toggle and Mastodon/Bluesky
connect/browse/disconnect alike, including reconnecting persisted servers on app startup
(`Main.notifyPageOfSharedMsg` forwards those top-level `Shared` messages into whichever page is
active). `subscriptions`' poll is just a distrustful fallback in case some future state change
doesn't route through `SharedMsg`, so it can be slow.

-}
fetchNewFeeds : Shared.Model -> Model -> ( Model, Effect Msg )
fetchNewFeeds shared model =
    let
        sourcesToFetch : List FeedSource
        sourcesToFetch =
            relevantFeedSources shared model
                |> List.filter
                    (\source ->
                        case Dict.get (feedSourceKey source) model.postsByServer of
                            Nothing ->
                                True

                            Just feed ->
                                feed.accountId /= feedSourceAccountId shared source
                    )
    in
    refetchFeeds shared model sourcesToFetch


{-| Re-fetches every relevant server, plus every enabled Bluesky account (unconditionally -- unlike
`fetchNewFeeds`, a changed search has to override every already-Loaded feed, not just sources whose
acting account changed) and persists the new `search_text`/`context` to the URL -- the single path
`SearchDebounceElapsed`, `ContextChanged`, and `ClearSearchClicked` all funnel through. Bluesky is
included here (unlike `MastodonInstance`, which has no search of its own -- see `refetchFeeds`'s own
doc) since `fetchFeedSource` actually does something different with a changed `model.searchText` for
it (`Bluesky.searchPosts` instead of `Bluesky.fetchPosts`), gated the same way
`relevantFeedSources` gates it off entirely: only while `model.author == Nothing`, since a Bluesky
network-wide search has no way to scope itself to one profile's own posts the way a real `GetPosts`
request can.
-}
applySearchChange : Shared.Model -> Model -> ( Model, Effect Msg )
applySearchChange shared model =
    let
        sourcesToRefetch : List FeedSource
        sourcesToRefetch =
            List.map RellmServer (relevantServers shared model)
                ++ (if model.author == Nothing then
                        List.map BlueskyFeed (List.filter .enabled shared.accounts.blueskyAccounts)

                    else
                        []
                   )

        ( refetchedModel, refetchEffect ) =
            refetchFeeds shared model sourcesToRefetch
    in
    ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )


{-| Reacts to `Shared.CreateNewPanel`'s own `GotSaveResult` succeeding --
splices a freshly-created `CreateNewPanel.CreatedPost` straight into this
page's already-fetched `postsByServer` (so the poster sees their own new post
immediately, no round-trip needed) rather than waiting on the next `Poll`/
account-change refetch to surface it. Ignored entirely unless it's actually
relevant to what's currently on screen: a `CreatedEvent` (irrelevant here --
`EventsPage` handles that half), a host that isn't one of `relevantServers`
(e.g. some other federated server this feed doesn't show), or a search/tab
state a brand-new post wouldn't belong in anyway (`model.tab ==
PostsBeforeDate`, an explicit past cutoff a just-created "now" post has no
business appearing under, or `model.context == REPLY`, since this panel only
ever creates top-level posts) are all left untouched.

While there's active search text, a locally-spliced-in post wouldn't actually
match the search server-side, so this instead falls back to
`applySearchChange`'s own full re-fetch -- the one case here that's a genuine
refresh rather than a purely local update.

-}
applyCreatedItem : Shared.Model -> CreateNewPanel.CreatedItem -> Model -> ( Model, Effect Msg )
applyCreatedItem shared createdItem model =
    case createdItem of
        CreateNewPanel.CreatedEvent _ _ ->
            ( model, Effect.none )

        CreateNewPanel.CreatedPost host post ->
            if model.tab == RecentPosts && model.context == POST && List.member host (List.map .frontendHost (relevantServers shared model)) then
                if String.isEmpty (String.trim model.searchText) then
                    ( { model
                        | postsByServer =
                            Dict.update host (Maybe.map (\feed -> { feed | status = prependPost post feed.status })) model.postsByServer
                      }
                        |> syncAnimations
                    , Effect.none
                    )

                else
                    applySearchChange shared model

            else
                ( model, Effect.none )


prependPost : Post -> ServerPosts -> ServerPosts
prependPost post status =
    case status of
        Loaded posts ->
            Loaded (post :: posts)

        _ ->
            status


{-| Keeps `Shared.Breadcrumbs` pointed at this feed's own root: `FromServerHost
mainFrontendHost` for an unfiltered feed (`model.author == Nothing`, e.g.
`Pages.Posts`), or `FromUser` the already-resolved author once one's known
(`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts`, which only ever call
`init` once their own `Resolver` has actually loaded the `User` -- see
`Pages.UsernameOrCustomTab_.Posts.update`) -- mirrors
`Components.Pages.UserProfilePage.setBreadcrumbsHost`, reissued after every
`update`, a no-op once already in sync via the same equality check.

Always `Effect.none` for an embedded copy (`model.embeddedPage`, e.g.
`Pages.Home_`'s or `Components.Pages.UserProfilePage`'s own) -- the embedding
page already owns `Shared.Breadcrumbs` itself, so this copy asserting a root
of its own on every `update` (including every animation tick, e.g. from
`postAnimations`) would otherwise fight the real owner for it, flickering
between the two roots whenever this page's `update` fires more often than the
embedding page's own (previously the actual cause of a breadcrumb flicker
during `Components.Pages.UserProfilePage`'s `EventsPage` animations).

-}
setBreadcrumbsRoot : Shared.Model -> Model -> Effect Msg
setBreadcrumbsRoot shared model =
    if model.embeddedPage then
        Effect.none

    else
        let
            ( root, host ) =
                case model.author of
                    Just ( authorHost, user ) ->
                        ( Breadcrumbs.FromUser user, authorHost )

                    Nothing ->
                        ( Breadcrumbs.FromServerHost shared.accounts.mainFrontendHost, shared.accounts.mainFrontendHost )
        in
        if shared.breadcrumbs.root == Just root then
            Effect.none

        else
            Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot root host []))


{-| Persists `model.searchText`/`model.context`/`model.tab`'s own
`publishedBefore` cutoff to the URL as `search_text`/`context`/
`published_before` query params, via `replaceUrl` (not the navigation
function `pushUrl` -- editing the search box/date input shouldn't spam
browser history with one entry per debounce fire). Each omitted entirely
while at its default (blank search, `POST` context, `RecentPosts` tab), so
the common case keeps a clean URL. Query-string-only navigation like this
doesn't re-trigger this page's `init` -- see `Main.elm`'s `ChangedUrl`
handler, which only does that when `url.path` itself changes. Built as one
combined list (rather than each concern pushing its own `replaceUrl`
independently) because `Browser.Navigation.replaceUrl`/`Url.Builder.toQuery`
replace the _whole_ query string -- independent single-param pushes would
each silently wipe out whatever the others had just set. Mirrors
`Components.Pages.EventsPage.pushUrl`/`queryParams`.
-}
pushUrl : Model -> Effect Msg
pushUrl model =
    let
        searchTextParam : List Url.Builder.QueryParameter
        searchTextParam =
            if String.isEmpty (String.trim model.searchText) then
                []

            else
                [ Url.Builder.string "search_text" model.searchText ]

        contextParam : List Url.Builder.QueryParameter
        contextParam =
            if model.context == POST then
                []

            else
                [ Url.Builder.string "context" (postContextParam model.context) ]

        publishedBeforeParam : List Url.Builder.QueryParameter
        publishedBeforeParam =
            case ( model.tab, model.publishedBefore ) of
                ( PostsBeforeDate, Just cutoff ) ->
                    [ Url.Builder.string "published_before" (Conversions.isoUtcString cutoff) ]

                _ ->
                    []
    in
    Browser.Navigation.replaceUrl model.navKey (model.path ++ Url.Builder.toQuery (searchTextParam ++ contextParam ++ publishedBeforeParam))
        |> Effect.fromCmd


{-| `post`/`reply` as sent via `search_text`/`context`'s URL query param and
`searchRowView`'s `<select>` `value`/`onInput` -- lowercase since it's the
URL-facing form; `postContextFromParam` reads it back case-insensitively, so
`?context=REPLY`/`?context=Reply`/etc. (e.g. a hand-edited or older link)
still work.
-}
postContextParam : PostContext -> String
postContextParam context =
    case context of
        REPLY ->
            "reply"

        _ ->
            "post"


{-| Case-insensitive inverse of `postContextParam`. Any other `PostContext`
(there are more, but only `POST`/`REPLY` are offered in the chooser -- see
`searchRowView`) round-trips back to `Nothing`/is left alone.
-}
postContextFromParam : String -> Maybe PostContext
postContextFromParam param =
    case String.toUpper param of
        "POST" ->
            Just POST

        "REPLY" ->
            Just REPLY

        _ ->
            Nothing


{-| Title-cased display label for `searchRowView`'s context chooser --
`postContextParam`/`postContextFromParam` handle the URL/`<select>` `value`
round-trip separately, since those are deliberately not title-cased.
-}
postContextLabel : PostContext -> String
postContextLabel context =
    case context of
        REPLY ->
            "Replies"

        _ ->
            "Posts"



-- ANIMATION


{-| Identifies a post independently of which server/account fetched it, for
`postAnimations` -- `postHref`'s `id@host` convention is reused here purely as
a unique dict key, not as a route.
-}
postAnimationKey : String -> Post -> String
postAnimationKey host post =
    host ++ "@" ++ post.id


{-| Reconciles `postAnimations` with the posts currently `Loaded` in `postsByServer` (real servers
and Mastodon/Bluesky feeds alike, now that both live in the same dict -- see `FeedSource`'s own doc):
starts a fade-in for newly-seen posts, a fade-out for posts that dropped out (rather than deleting
them outright), and un-interrupts a still-fading-out post that reappeared. Safe/cheap to call after
every `postsByServer` change, so `update` just calls it unconditionally wherever it might have
changed. `RemovePost` is what actually drops a gone post's animation entry once its fade-out
finishes. See `UI.Flip.syncAnimations` for the shared reconciliation logic this hands its own
`PostAnimation` shape to (mirrored by `Components.Pages.UsersPage.syncAnimations`).

Every `Loaded` list is filtered by `model.context` here regardless of source -- a no-op for a real
server's response (already scoped/filtered server-side to this exact request), but load-bearing for
a Mastodon/Bluesky feed, which has no notion of `model.context` at all: it's just whatever mix of
POST/REPLY the account's own feed happened to contain, so this is the one place that still has to
filter it by hand.

-}
syncAnimations : Model -> Model
syncAnimations model =
    let
        currentPosts : Dict String ( String, Post )
        currentPosts =
            model.postsByServer
                |> Dict.toList
                |> List.concatMap
                    (\( host, feed ) ->
                        case feed.status of
                            Loaded posts ->
                                posts
                                    |> List.filter (\post -> post.context == model.context)
                                    |> List.map (\post -> ( postAnimationKey host post, ( host, post ) ))

                            _ ->
                                []
                    )
                |> Dict.fromList
    in
    { model
        | postAnimations =
            UI.Flip.syncAnimations
                RemovePost
                (\( host, post ) -> { host = host, post = post, flip = UI.Flip.enter })
                (\( host, post ) anim -> { anim | host = host, post = post })
                currentPosts
                model.postAnimations
    }



-- VIEW


{-| `showSearchRow` hides `searchRowView` (the search box + POST/REPLY context chooser together,
including its own trailing `exportButtonView`) when `False` -- used by `Pages.Home_`, which shows
its own `EventsPage`'s search box instead and keeps this module's `model.searchText` in sync with
it behind the scenes (see `Pages.Home_.update`'s cross-sync) rather than showing two redundant
boxes. Every other caller passes `True`, preserving the previous always-shown behavior.

A "Subscribe" link is exactly as useful without the search row as with it, though -- both
`Pages.Home_`'s embedded feed and `Components.Pages.UserProfilePage`'s own embedded posts list
(where `model.author` is already set, so `feedUrl` comes out `user_id`-scoped for free) still
want one. Since `showSearchRow = False` callers already render their own static heading
(`Pages.Home_.heading`/`Components.Pages.UserProfilePage.postsHeading`, both external to this
module -- see `recentPostsTabsView`'s own doc), `exportButtonView` is exposed for them to place
directly beside their own heading rather than this module inserting an otherwise-empty row of
its own for just that one button.

`showAuthorHeading` hides `authorHeadingView` (the "Posts | <name>" heading) when `False`
-- used by `Components.Pages.UserProfilePage`, which embeds this module a level below its own
already-shown username/avatar header (see `profileDetail`), so a second copy of the same name
would be redundant. Every other caller passes `True`, preserving the previous always-shown
(whenever `model.author` is `Just`) behavior.

-}
view : Shared.Model -> Bool -> Bool -> Model -> Html Msg
view shared showSearchRow showAuthorHeading model =
    div []
        [ recentPostsTabsView shared model
        , if showAuthorHeading then
            authorHeadingView shared model.author model.context

          else
            text ""
        , if showSearchRow then
            searchRowView shared model

          else
            text ""
        , postsListView shared model
        ]


{-| The "Recent Posts"/"Recent Replies" heading's replacement on the
standalone, unfiltered Posts page (`model.author == Nothing`, `not
model.embeddedPage` -- `text ""` otherwise, so every other caller of `view`
is unaffected): two tabs (mirrors
`Components.Pages.EventsPage.tabsView`'s own look/structure), `RecentPosts`
(a plain pill button, carrying the same "Recent Posts"/"Recent Replies" label
`Pages.Posts`' own heading used to) and `PostsBeforeDate` (a `div` rather than
a `button`, since it nests a real `<input type="datetime-local">` and nesting
interactive content inside a `<button>` is invalid HTML) -- clicking either
(including anywhere in the second tab, to open the date input's native
picker, since the click still bubbles up to the wrapping `div`) or actually
changing the date both switch to it, per `TabChanged`'s own doc. Absent
entirely for `Pages.Home_`'s embedded copy (still gets its own static
"Recent Posts"/"Recent Replies" heading, see `Pages.Home_.heading`) and for
any author-scoped copy (`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts`/
`Components.Pages.UserProfilePage`, which show `authorHeadingView` instead).
-}
recentPostsTabsView : Shared.Model -> Model -> Html Msg
recentPostsTabsView shared model =
    if model.author /= Nothing || model.embeddedPage then
        text ""

    else
        div [ class "filter-tabs-bar" ]
            [ button
                [ classes
                    ("filter-tab"
                        :: "filter-tab-primary"
                        :: (if model.tab == RecentPosts then
                                [ "background-color-primary" ]

                            else
                                []
                           )
                    )
                , onClick (TabChanged RecentPosts)
                ]
                [ text (recentPostsLabel model.context) ]
            , div
                [ classes
                    ("filter-tab"
                        :: (if model.tab == PostsBeforeDate then
                                [ "background-color-primary" ]

                            else
                                []
                           )
                    )
                , onClick (TabChanged PostsBeforeDate)
                ]
                [ text (postsBeforeLabel model.context ++ " ")
                , input
                    [ type_ "datetime-local"
                    , class "filter-tab-date-input"
                    , value
                        (SharedTime.formatDateTimeLocalInput
                            shared.time.browserTimeZone.zone
                            (Maybe.withDefault (Time.millisToPosix 0) model.publishedBefore)
                        )
                    , onInput PublishedBeforeInputChanged
                    ]
                    []
                ]
            ]


{-| "Recent Posts"/"Recent Replies", matching `context` -- mirrors
`Pages.Posts.heading`'s old label exactly (this view replaces that page's own
static heading, see `recentPostsTabsView`'s own doc).
-}
recentPostsLabel : PostContext -> String
recentPostsLabel context =
    case context of
        REPLY ->
            "Recent Replies"

        _ ->
            "Recent Posts"


{-| "Posts Before"/"Replies Before", matching `context` -- `recentPostsTabsView`'s
own `PostsBeforeDate` tab label, immediately followed by its `<input
type="datetime-local">`.
-}
postsBeforeLabel : PostContext -> String
postsBeforeLabel context =
    case context of
        REPLY ->
            "Replies Before"

        _ ->
            "Posts Before"


{-| Search box (debounced, see `SearchTextChanged`/`SearchDebounceElapsed`)
plus a POST/REPLY context chooser, side by side in the generic
`.filter-controls-row`/`.filter-search-field`/`.filter-controls-trailing`
(`ui/filter_bar.css`) -- only those two contexts are offered for now
(`Proto.Rellm.PostContext` has others, e.g. `EVENT`, that don't apply to a
plain posts feed). The clear ("╳") button, styled like `UI.elm`'s
`fieldClearButton`/`.field-clear-button` (can't reuse that directly -- it's
hardcoded to `Shared.Msg`/`AccountsPanel.Msg`, not this module's own `Msg`),
only appears once there's search text to clear.
-}
searchRowView : Shared.Model -> Model -> Html Msg
searchRowView shared model =
    div [ class "filter-controls-row" ]
        [ div [ class "filter-search-field" ]
            [ input
                [ type_ "text"
                , class "filter-search-input"
                , placeholder <|
                    case model.context of
                        REPLY ->
                            "Search replies..."

                        _ ->
                            "Search posts..."
                , value model.searchText
                , onInput SearchTextChanged
                , onEscape ClearSearchClicked
                ]
                []
            , if String.isEmpty model.searchText then
                text ""

              else
                button
                    [ type_ "button"
                    , class "field-clear-button"
                    , onClick ClearSearchClicked
                    , title "Clear search"
                    ]
                    [ text "╳" ]
            ]
        , div [ class "filter-controls-trailing" ]
            [ select [ class "posts-search-context", onInput ContextChanged ]
                (List.map
                    (\context ->
                        option
                            [ value (postContextParam context)
                            , selected (model.context == context)
                            ]
                            [ text (postContextLabel context) ]
                    )
                    [ POST, REPLY ]
                )
            , exportButtonView shared model
            ]
        ]


{-| `kind`'s own subscription path (see `backend/src/web/rss_subscription.rs`/
`atom_subscription.rs`) -- `feedUrl`'s own query-string-appending half.
-}
feedKindPath : ExportFeedKind -> String
feedKindPath kind =
    case kind of
        Rss ->
            "/rss.xml"

        Atom ->
            "/atom.xml"


feedKindLabel : ExportFeedKind -> String
feedKindLabel kind =
    case kind of
        Rss ->
            "RSS"

        Atom ->
            "Atom"


{-| The backend's `kind`-formatted feed endpoint (`GET /rss.xml`/`GET /atom.xml`,
`?user_id={id}` once `model.author` scopes this listing to one user) -- mirrors
`Components.Pages.EventsPage.icsUrl` exactly, just parameterized over which of the two formats,
and serving Posts instead of Events.
-}
feedUrl : Shared.Model -> Model -> ExportFeedKind -> String
feedUrl shared model kind =
    case model.author of
        Just ( host, user ) ->
            "https://" ++ host ++ feedKindPath kind ++ Url.Builder.toQuery [ Url.Builder.string "user_id" user.id ]

        Nothing ->
            "https://" ++ shared.accounts.mainFrontendHost ++ feedKindPath kind


{-| The "Export" icon button -- sits at the end of `searchRowView`'s `.filter-controls-trailing`
when that's shown (`showSearchRow = True`), or is placed directly by an embedding caller
(`Pages.Home_`/`Components.Pages.UserProfilePage`, see `view`'s own doc) beside their own static
heading when it's not. Exposed from this module for exactly that second case. Mirrors
`Components.Pages.EventsPage.exportButtonView` almost exactly (same
`popover-anchor`/`popover-toggle`/`popover`/`popover-backdrop` structure from `ui/popover.css`),
just offering both RSS and Atom links/copy buttons side by side instead of one ICS link, since a
Posts feed can be subscribed to as either format (see `logic::sync_sources::feed_sync`'s own
"either syncs the same way" symmetry on the _pulling-in_ side -- this is the _serving-out_ side).
-}
exportButtonView : Shared.Model -> Model -> Html Msg
exportButtonView shared model =
    div [ classes [ "posts-export", "popover-anchor" ] ]
        [ button
            [ classes [ "filter-icon-button", "popover-toggle", "background-color-nav", openClosedClass model.exportPopoverOpen ]
            , onClick ExportClicked
            , title "Export posts (RSS/Atom)"
            , type_ "button"
            ]
            [ text "⤓" ]
        , div [ classes [ "popover-backdrop", openClosedClass model.exportPopoverOpen ], onClick ExportPopoverClosed ] []
        , div [ classes [ "posts-export-popover", "popover", openClosedClass model.exportPopoverOpen ] ]
            [ h3 [ class "posts-export-popover-heading" ]
                [ text "Subscribe to Posts" ]
            , p [] [ text "Works with Feedly, Inoreader, NetNewsWire, and most feed readers." ]
            , div [ class "posts-export-popover-links" ]
                (List.map
                    (\kind ->
                        span []
                            [ text (feedKindLabel kind ++ ": ")
                            , a
                                [ href (feedUrl shared model kind)
                                , target "_blank"
                                , class "posts-export-popover-link"
                                ]
                                [ text (feedUrl shared model kind) ]
                            ]
                    )
                    [ Rss, Atom ]
                )
            , div [ class "posts-export-popover-copy-row" ]
                (List.map
                    (\kind ->
                        button
                            [ classes [ "posts-export-popover-copy", "background-color-primary" ]
                            , onClick (CopyLinkClicked kind)
                            , type_ "button"
                            ]
                            [ span [ class "posts-export-popover-copy-icon" ] [ text "⎘" ]
                            , span [ class "posts-export-popover-copy-label" ]
                                [ text
                                    (if model.copyLinkCopied == Just kind then
                                        "Copied!"

                                     else
                                        "Copy " ++ feedKindLabel kind ++ " Link"
                                    )
                                ]
                            ]
                    )
                    [ Rss, Atom ]
                )
            ]
        ]


{-| Fires `msg` (and suppresses the key's default effect) when Escape is
pressed in a text input -- mirrors `UI.elm`'s `onEnter`, just for a different
key; defined locally rather than imported from there since `UI` is the
higher-level module that itself ends up depending on pages like this one.
-}
onEscape : msg -> Html.Attribute msg
onEscape msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Escape" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Escape key"
                )
        )


{-| "Posts"/"Replies" (matching `context` -- the same POST/REPLY chooser
`searchRowView` renders just below this) alone once there's an `author` to
filter by (even before that `User` -- already resolved by the caller, see
`init` -- has actually rendered), upgraded to "Posts | <name>" via
`Components.Users.ProfileHeading.nameHeader` (with that author's avatar, via
its resolved-host `RellmServer`/signed-in `Account`, if that host is
still a known server -- falling back to `ProfileHeading.usernameHeading`,
avatar-less, if not) -- absent entirely for `Pages.Home_`'s unfiltered feed
(`author == Nothing`), which supplies its own "Recent Posts"/"Recent Replies"
heading instead (see `Pages.Home_.heading`).
-}
authorHeadingView : Shared.Model -> Maybe ( String, User ) -> PostContext -> Html Msg
authorHeadingView shared maybeAuthor context =
    case maybeAuthor of
        Nothing ->
            text ""

        Just ( host, author ) ->
            let
                profileUrl : String
                profileUrl =
                    usernameHref "" shared.accounts.mainFrontendHost host author.username

                headingText : String
                headingText =
                    case context of
                        REPLY ->
                            "Replies"

                        _ ->
                            "Posts"
            in
            div [ class "posts-page-heading" ]
                [ h2 [] [ text headingText ]
                , a [ href profileUrl, class <| hostnameToCSSClass host ]
                    [ case RellmServers.rellmServerForHost shared.accounts.servers host of
                        Just server ->
                            ProfileHeading.nameHeader server (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host) author

                        Nothing ->
                            ProfileHeading.usernameHeading author
                    ]
                ]


{-| `model.postAnimations`, sorted most-recent-first by `Posts.postTimestamp`'s
own "published\_at || created\_at" logic -- but only while `model.searchText`
is blank: an active text search's results come back relevance-ranked (see
`backend/src/rpcs/posts/get_posts.rs`'s `get_search_posts`), and re-sorting by
recency here would throw that ranking away. Mirrors
`Components.Pages.EventsPage.visibleAnimations`'s own identical search gate.
-}
postsListView : Shared.Model -> Model -> Html Msg
postsListView shared model =
    let
        postsWord : String
        postsWord =
            case model.context of
                REPLY ->
                    "replies"

                _ ->
                    "posts"
    in
    if Dict.isEmpty model.postsByServer then
        p [ class "posts-empty" ] [ text <| "Connect to a server to see recent " ++ postsWord ++ "." ]

    else
        let
            sortedAnimations : List ( String, PostAnimation )
            sortedAnimations =
                model.postAnimations
                    |> Dict.toList
                    |> (if String.isEmpty (String.trim model.searchText) then
                            List.sortBy (\( _, anim ) -> -(Time.posixToMillis (Posts.postTimestamp anim.post)))

                        else
                            identity
                       )
        in
        if List.isEmpty sortedAnimations then
            p [ class "posts-empty" ] [ text <| "No " ++ postsWord ++ " yet." ]

        else
            Html.Keyed.node "div"
                [ class "posts-list flip-animated-column" ]
                (List.map (postAnimationView shared model.showSyncDestinations model.availableSyncDestinations model.pushStatuses) sortedAnimations)


{-| Wraps `Posts.postCard` in a fading/scaling/collapsing animated `<div>`
(see `syncAnimations`) -- the `.flip-collapsed` class (present while
`entering` or `removing`) is what makes `flip.css`'s `.flip-animated-item`
rules grow/shrink this wrapper's own height, which is what makes the _other_
posts slide smoothly into the space this one leaves/needs, on top of its own
fade -- see that rule's doc comment for how. The inner `div` is purely a clip
layer (`.flip-animated-item > *` in `flip.css`, invisible/borderless) so the
inter-post spacing it holds as `padding-bottom` can shrink away smoothly
along with everything else, rather than showing up inside `.post-card`'s own
border; it also carries `pointer-events: none` while `removing` so a
fading-out card (e.g. from a just-disabled server) can't be clicked/starred
while it's on its way out.
-}
postAnimationView : Shared.Model -> Bool -> Maybe (List SyncDestination) -> Dict String SubmitStatus -> ( String, PostAnimation ) -> ( String, Html Msg )
postAnimationView shared showSyncDestinations availableSyncDestinations pushStatuses ( key, anim ) =
    let
        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if anim.flip.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    ( key
    , div (UI.Flip.itemAttributes UI.Flip.Vertical anim.flip False)
        [ div pointerEventsAttr [ postCardView shared showSyncDestinations availableSyncDestinations pushStatuses ( anim.host, anim.post ) ] ]
    )


postCardView : Shared.Model -> Bool -> Maybe (List SyncDestination) -> Dict String SubmitStatus -> ( String, Post ) -> Html Msg
postCardView shared showSyncDestinations availableSyncDestinations pushStatuses ( host, post ) =
    let
        displayPost : Post
        displayPost =
            StarredPanel.freshestPost host post shared.panels.starredPanel

        starred : Bool
        starred =
            StarredPanel.isStarred host displayPost shared.panels.starredPanel

        onStarClicked : Maybe Msg
        onStarClicked =
            StarredPanel.toggleStarMsg shared.accounts host displayPost
                |> Maybe.map (Shared.StarredPanelMsg >> SharedMsg)

        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost shared.accounts.servers host

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host

        onMediaClicked : String -> Msg
        onMediaClicked mediaId =
            SharedMsg (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open displayPost.media (Just displayPost) mediaId host))

        isPushing : String -> Bool
        isPushing destinationId =
            Dict.get (pushStatusKey displayPost.id destinationId) pushStatuses == Just Submitting

        pushError : String -> Maybe String
        pushError destinationId =
            case Dict.get (pushStatusKey displayPost.id destinationId) pushStatuses of
                Just (SubmitFailed err) ->
                    Just err

                _ ->
                    Nothing

        onPush : String -> Msg
        onPush destinationId =
            PushPostToDestination host displayPost.id destinationId

        onDelete : String -> String -> Msg
        onDelete destinationId destinationLabel =
            SharedMsg (Shared.RequestDelete (Shared.ConfirmPostSyncDestinationDelete displayPost destinationId destinationLabel host))
    in
    Posts.postCard
        shared.time
        shared.basePath
        shared.accounts.mainFrontendHost
        host
        maybeServer
        maybeAccount
        onMediaClicked
        False
        False
        starred
        onStarClicked
        showSyncDestinations
        availableSyncDestinations
        isPushing
        pushError
        onPush
        onDelete
        displayPost
