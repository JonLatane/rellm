module Shared exposing
    ( DeleteConfirmation(..)
    , Flags
    , Model
    , Msg(..)
    , NavAnimationState
    , PageSlide(..)
    , ThemePreference(..)
    , basePathFromPath
    , effectiveDarkMode
    , forcedDarkMode
    , init
    , isCountabilibarSync
    , notifiesPages
    , normalizeUrl
    , subscriptions
    , themePreferenceLabel
    , update
    )

{-| The app-wide state: composes `Shared.AccountsPanel` (known servers,
signed-into accounts, login/add-server forms, and -- via
`Shared.AccountsPanel.DebugTab` -- the Accounts
Panel's Debug tab, shown when any signed-in account has `ADMIN`), plus the
appearance (dark/light/auto) setting that doesn't belong to it.
-}

import Browser.Dom as Dom
import Browser.Events
import Browser.Navigation as Nav
import Components.Events as Events
import Components.MediaMaintenance as MediaMaintenance
import Components.MediaRenderer as MediaRenderer
import Components.Pages.MessagesPage as MessagesPage
import Components.Posts as Posts
import Components.SyncSources as SyncSources
import Components.Users as Users
import Dict
import Grpc
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Process
import Proto.Google.Protobuf
import Proto.Rellm exposing (ContactMethod, Event, GetMediaResponse, Media, MediaReference, Occasion, Post, SyncSource, User, defaultGetMediaRequest)
import Proto.Rellm.ContactConsentState exposing (ContactConsentState(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.WebUserInterface exposing (WebUserInterface(..))
import Request exposing (Request)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.AudioPlayerPanel as AudioPlayerPanel
import Shared.VideoPlayerPanel as VideoPlayerPanel
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Federation.Actions as FederationActions
import Shared.Federation.RellmLinks as RellmLinks
import Shared.BrowserInfo as BrowserInfo
import Shared.Countabilibar as Countabilibar
import Shared.CreateNewPanel as CreateNewPanel
import Shared.FederatedAuth as FederatedAuth
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MediaGeneratorPanel as MediaGeneratorPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.MessagingPanel as MessagingPanel
import Shared.EventsCache as EventsCache
import Shared.MyMediaPanel as MyMediaPanel
import Shared.PostsCache as PostsCache
import Shared.PushNotificationLink as PushNotificationLink
import Shared.QuoteLinks as QuoteLinks
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import Shared.UserPreferences as UserPreferences
import Task
import Time
import TimeZone
import UI.Responsive as Responsive
import Url exposing (Url)


type alias Model =
    -- Known servers, signed-into accounts, login/add-server forms -- kept as
    -- its own top-level field (rather than folded into `panels`) since it's
    -- read from all over the app (view code on nearly every page), not just
    -- panel-adjacent code.
    { accounts : AccountsPanel.Model

    -- See `Panels` for the rest of the app-wide panels.
    , panels : Panels
    , breadcrumbs : Breadcrumbs.Model

    -- The row of post/event counts below the breadcrumbs, fed by `PostsPage`/`EventsPage` -- see
    -- `Shared.Countabilibar`. Reset (by `Main`) on every route change.
    , countabilibar : Countabilibar.Model

    -- The quoted posts fetched so far for Rellm posts whose `link` points at another post (see
    -- `Shared.QuoteLinks`) -- app-wide so a post quoted by many cards is fetched once, and so the card
    -- on a feed and the preview in `CreateNewPanel` share it.
    , quoteLinks : QuoteLinks.Model

    -- Posts feeds kept in memory so going back to one shows it as it was -- see `Shared.PostsCache`.
    , postsCache : PostsCache.Model

    -- The same for events feeds -- see `Shared.EventsCache`.
    , eventsCache : EventsCache.Model

    -- See `Theme` for `preference`/`systemPrefersDark` themselves.
    , theme : Theme

    -- See `Shared.UserPreferences` for `prefersCalendar` itself.
    , userPreferences : UserPreferences.Model

    -- The path prefix the app is being served under -- "" from `/`, "/elm"
    -- from `/elm` (see `backend/src/web/elm_web.rs`) -- immutable for the
    -- session, same as `AccountsPanel.Model`'s `browsingHost`. `Main.elm`
    -- strips this from every `Url` before routing (see `normalizeUrl`) so
    -- `Gen.Route.fromUrl` always sees app-relative paths regardless of which
    -- host route served it; view code (see `UI.navLink`) prepends it back
    -- onto any `Gen.Route.toHref` output so links/history stay under the
    -- right mount.
    , basePath : String

    -- Detected once from `navigator.userAgent` (flag `userAgent`) -- display-only, see
    -- `Shared.BrowserInfo`.
    , browser : BrowserInfo.Browser

    -- Drives `UI.scrollPreserver`: a tall spacer at the bottom of `main_`,
    -- shown for the first 2s after navigating *back* to a page (never a
    -- fresh link click) so its restored-but-possibly-still-loading content
    -- can't yank the scroll position around while it fills back in. See
    -- `Main.elm`'s `ChangedUrl`, which fires `ShowScrollPreserver` only for
    -- navigations it recognizes as the browser's back button.
    , scrollPreserverVisible : Bool

    -- Which side the page just navigated to should slide in from -- `Just` only for a navigation
    -- between top-nav tabs (see `UI.CustomNav.pageSlideFor`, set by `Main.elm`'s `ChangedUrl`),
    -- `Nothing` for every other navigation. Consumed by `UI.layout`'s keyed page wrapper.
    , pageSlide : Maybe PageSlide

    -- Drives the Home link's scroll-triggered shrink animation -- kept in
    -- sync via `.nav-links-scroll`'s `scroll` event
    -- (`UI.navLinksScrollDecoder` -> `NavLinksScrolled`). See
    -- `NavAnimationState`.
    , navAnimationState : NavAnimationState

    -- The browser's current window size, kept live via `Browser.Events.onResize`
    -- (see `subscriptions`) after an initial `Browser.Dom.getViewport` read in
    -- `init`. Only consulted for `UI.Responsive.isNarrow` -- deciding whether
    -- the Accounts Panel and Starred Panel should close one another when
    -- the other opens (see `update`'s `AccountsPanelMsg`/`StarredPanelMsg`
    -- branches), since both are full-width slide-out panels on narrow screens
    -- and CSS alone can't reach into another panel's state.
    , windowSize : Responsive.WindowSize

    -- See `Shared.Time` for `browserTimeZone`/`now` themselves -- bundled
    -- into one type alias since every call site that needs one of these
    -- tends to need the other too (see its own doc).
    , time : SharedTime.Model

    -- Which video media ids have been clicked to play -- see
    -- `Components.MediaRenderer`'s own "Click-to-play video previews" doc. A single
    -- app-wide instance (not folded into `panels`, since it's not an overlay -- it's read by
    -- ordinary in-page content, `postCard`/`postDetail`/`eventCard` and friends) so a video
    -- clicked-to-play in one rendering of a Post/Event (e.g. a pinned post) shows as playing in
    -- every other rendering of the same media too.
    , mediaRenderer : MediaRenderer.Model
    }


type Msg
    = AccountsPanelMsg AccountsPanel.Msg
    | FederatedAuthMsg FederatedAuth.Msg
    | StarredPanelMsg StarredPanel.Msg
    | UserPreferencesMsg UserPreferences.Msg
    | MarkdownPanelMsg MarkdownPanel.Msg
    | MediaGeneratorPanelMsg MediaGeneratorPanel.Msg
    | MediaViewerPanelMsg MediaViewerPanel.Msg
    | AudioPlayerPanelMsg AudioPlayerPanel.Msg
    | VideoPlayerPanelMsg VideoPlayerPanel.Msg
      -- The URL fragment changed (`Main`'s `ChangedUrl`): a `#track-<id>` one opens that track in the audio
      -- player -- see `AudioPlayerPanel.trackLinkFromFragment` -- and a `#video-<id>` one that video (`videoLinkFromFragment`).
    | TrackLinkChanged (Maybe String)
    | -- The server the link named (the main one when it named none), and what it returned.
      -- (The `Int` is the player's `selectionGeneration` when the request was made: a reply is dropped if the user has
      -- started something else, or closed the player, since.)
      GotLinkedTrack String Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
      -- The same for a `#video-<id>` link.
    | GotLinkedVideo String Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
      -- A post card's audio moving to the audio bar (`Ports.audioHandoffRequested`); `Nothing` is a malformed one.
    | AudioHandoffRequested (Maybe AudioPlayerPanel.Handoff)
      -- The `selectionGeneration` the request was made at: a reply is dropped if the user has started something else (or closed
      -- the player) since.
    | GotHandoffTrack AudioPlayerPanel.Handoff Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
    | MediaRendererMsg MediaRenderer.Msg
    | MyMediaPanelMsg MyMediaPanel.Msg
    | MyMediaPanelOpenForAccount RellmAccount
    | ProfileSectionLinkClicked RellmAccount String
      -- `UI.accountAvatarMenuView`'s nested "Contact Methods" item (see
      -- `AccountsPanel.Model.focusedAccountPhoneEdit`/etc) -- the actual RPC-calling half of that
      -- feature. `AccountsPanel.elm` can't call `Components.Users.updateUser`/
      -- `startContactMethodVerification`/`verifyContactMethod` itself (`Components.Users` already
      -- imports `Shared.AccountsPanel`, so the reverse would be a cycle) -- same reason
      -- `MyMediaPanelOpenForAccount` above lives here rather than in `AccountsPanel.update`. Each
      -- Clicked variant fires the RPC; each `Got*TaskResult` decomposes the raw
      -- `Task`/`( Maybe AccountsPanel.Msg, _ )` result -- forwarding the token-refresh half (if any)
      -- the same way `accountsPanelEffect` does for `Components.Pages.UserProfilePage`, then folding
      -- the actual `User`/`ContactMethod` into `AccountsPanel.Model` via its own same-named
      -- `Got*Result` `Msg` (`updateFocusedAccountFromUser`/`updateFocusedAccountPhone`). Deleting
      -- (`GotPhoneDeleteResult`/`GotEmailDeleteResult`, up above with the other `DeleteConfirmation`-
      -- driven results) isn't among these -- it's shared with `Components.Pages.UserProfilePage`'s
      -- own "Delete Phone"/"Delete Email", so it goes through `ConfirmDelete` (`ConfirmPhoneDelete`/
      -- `ConfirmEmailDelete`) instead of this Accounts-Panel-only Clicked/`Got*TaskResult` pairing.
    | ContactMethodPhoneSaveClicked
    | ContactMethodEmailSaveClicked
    | ContactMethodPhoneConsentToggled
    | ContactMethodEmailConsentToggled
    | ContactMethodStartPhoneVerificationClicked
    | ContactMethodVerifyPhoneCodeClicked
    | GotContactMethodPhoneSaveTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | GotContactMethodEmailSaveTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | GotContactMethodPhoneConsentTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | GotContactMethodEmailConsentTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | GotContactMethodStartPhoneVerificationTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod ))
    | GotContactMethodVerifyPhoneCodeTaskResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod ))
    | CreateNewPanelMsg CreateNewPanel.Msg
    | QuoteLinksMsg QuoteLinks.Msg
      -- What `PostsPage` sends to save (or forget) its feed -- never forwarded back into a page (see `notifiesPages`).
    | PostsCacheMsg PostsCache.Msg
      -- `EventsPage`'s equivalent (and what an event's own page sends to forget feeds it has made stale).
    | EventsCacheMsg EventsCache.Msg
    | MessagingPanelMsg MessagingPanel.Msg
    | CloseAllPanels
    | BreadcrumbsMsg Breadcrumbs.Msg
    | CountabilibarMsg Countabilibar.Msg
      -- What `PostsPage`/`EventsPage` send to keep the counts in step with what they show (see
      -- `Countabilibar.syncMsg`) -- applied exactly like `CountabilibarMsg`, but a separate constructor
      -- because it must never be forwarded back into a page (see `notifiesPages`) or mistaken for an
      -- echo of one (see `isCountabilibarSync`).
    | CountabilibarSync Countabilibar.Msg
    | ThemePreferenceClicked
    | SystemPrefersDarkChanged Bool
    | RequestDelete DeleteConfirmation
    | CancelDelete
    | ConfirmDelete
      -- `ConfirmDelete`'s own handling of `ConfirmSyncSourceDelete`/
      -- `ConfirmPostDelete`/`ConfirmEventDelete`/`ConfirmUserDelete` fires
      -- the `DeleteSyncSource`/`DeletePost`/`DeleteEvent`/`DeleteUser`
      -- RPC directly (unlike every other `DeleteConfirmation`, none of these
      -- four is owned by any Shared-owned panel `Shared.update` could
      -- delegate to) -- these are their results. Forwarded, like every
      -- `Shared.Msg`, into whichever page is active
      -- (`Main.notifyPageOfSharedMsg`), so
      -- `Components.Pages.UserProfilePage`/`Pages.Post.PostId_`/
      -- `Pages.Event.PostId_`'s own `SharedMsg` handling can update their
      -- own list/navigate away on success.
    | GotSyncSourceDeleteResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
      -- `ConfirmDeleteLinkPreviewImages`'s result -- forwarded to the active page like the others;
      -- `SettingsTab.applySharedMsg` shows it next to its Media Settings buttons.
    | GotLinkPreviewImagesDeleteResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
    | GotPostDeleteResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- `ConfirmFederatedPostDelete`'s result: a Mastodon/Bluesky post deleted over that service's own HTTP
      -- API (hence `Http.Error`), carrying the `AccountsPanel.Msg` for a refreshed token, if any.
    | GotFederatedPostDeleteResult (Result Http.Error (Maybe AccountsPanel.Msg))
    | GotEventDeleteResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Event ))
      -- `ConfirmOccasionDelete`'s own result -- unlike `GotEventDeleteResult`
      -- (after which nothing about the deleted `Event` is left to look at, so
      -- `Pages.Event.PostId_` just navigates Home), the `Event` here is the
      -- *survivor*: `DeleteRemovedOccasions`'s own return value, still
      -- carrying every other `Occasion` that wasn't deleted -- letting
      -- that page navigate to one of those instead, keeping the viewer on the
      -- same Event rather than bouncing them away from it entirely.
    | GotOccasionDeleteResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Event ))
      -- `ConfirmOccasionSyncDestinationDelete`'s own result -- `host`
      -- mirrors `Components.Pages.EventsPage.GotPushResult`'s own (this is
      -- the Delete button's counterpart to that Push button's result), so
      -- whichever page is active (currently only
      -- `Components.Pages.UserProfilePage`'s embedded `EventsPage` copy) can
      -- re-scope its refetch to just `host`'s server the same way.
    | GotOccasionSyncDestinationDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
      -- `ConfirmNewAnonymousRsvp` confirmed -- occasion id, then `targetHost`.
    | NewAnonymousRsvpConfirmed String String
      -- `ConfirmPostSyncDestinationDelete`'s own result -- mirrors
      -- `GotOccasionSyncDestinationDeleteResult`'s own doc exactly, just
      -- for `Components.Pages.PostPage`/`Components.Pages.UserProfilePage`'s
      -- embedded `PostsPage` copy instead of `EventsPage`.
    | GotPostSyncDestinationDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
      -- The trailing `User`/`String` are the deleted user/acting `targetHost`
      -- (mirroring `ConfirmUserDelete`'s own two extra fields) -- unlike
      -- `GotPostDeleteResult`/`GotEventDeleteResult`, this needs them back:
      -- a successful delete also has to drop that user's account from
      -- `AccountsPanel`'s own locally-known list, if it's in there at all
      -- -- whether that's the viewer's own account (a self-delete) or some
      -- other, possibly-disabled account an Admin had signed into and left
      -- disabled (e.g. after banning them) -- and that decision can only
      -- be made once, here in `Shared.update` itself --
      -- `Components.Pages.UserProfilePage`'s own `SharedMsg` handling of
      -- this same message can't do it instead, since
      -- `Main.notifyPageOfSharedMsg` (which delivers a top-level
      -- `Shared.Msg` like this one to a page) silently drops any *new*
      -- `Shared.Msg` a page's own `SharedMsg` branch forwards back in
      -- response -- only an echo of the incoming message itself is safe to
      -- forward that way, per its own doc.
    | GotUserDeleteResult User String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty ))
      -- `ConfirmPhoneDelete`/`ConfirmEmailDelete`'s own results -- the trailing `String` is the
      -- acting `targetHost` (same convention as the other `DeleteConfirmation`-driven results
      -- above), used to find the matching `RellmAccount` in `model.accounts.accounts` (by that host
      -- + the updated `User.id`) to fold the now-`Nothing` `phone`/`email` into, mirroring
      -- `GotUserDeleteResult`'s own "can only be done here, not in a page's own `SharedMsg`" reasoning
      -- for why that merge lives in `Shared.update` rather than `Components.Pages.UserProfilePage`'s.
      -- The full updated `User` (not just `()`/`Empty`) rides along so that page's own `SharedMsg`
      -- handling can still merge it into `model.resolver` directly, no extra refetch needed.
    | GotPhoneDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | GotEmailDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | ShowScrollPreserver
    | HideScrollPreserver
    | UncollapseHome
    | HomeLinkClicked Bool
    | ScrollToTop
    | NavLinksScrolled { scrollLeft : Float, scrollWidth : Float, clientWidth : Float }
    | NavigateExternal String
    | WindowResized Int Int
      -- `Ports.pushNotificationClicked`: a push notification for another server (cross-origin from
      -- this tab, so `service-worker.js` couldn't navigate to it itself) was clicked -- the payload
      -- is its absolute URL. See `Shared.PushNotificationLink`.
    | PushNotificationClicked String
    | GotTimeZone String Time.Zone
    | GotNow Time.Posix
    | NoOp


type alias Flags =
    Decode.Value


{-| The app-wide appearance (dark/light/auto) setting -- see `Model.theme`.
Bundled into one type since `effectiveDarkMode` always needs both together:
`preference` alone doesn't say whether `Auto` currently means dark or
light, and `systemPrefersDark` alone doesn't say whether the user has
overridden it.
-}
type alias Theme =
    { preference : ThemePreference
    , systemPrefersDark : Bool
    }


{-| The user's chosen appearance. `Auto` follows `systemPrefersDark`; `Light`/
`Dark` force it regardless of the system.
-}
type ThemePreference
    = ThemeAuto
    | ThemeLight
    | ThemeDark


{-| Something the user has clicked "delete" on, awaiting confirmation --
`UI.deleteConfirmationModal` is one shared dialog for all of these, rather
than each having its own bespoke confirmation step (compare
`AccountsPanel.PendingCreateAccount`, which stays separate since Create
Account's confirmation isn't a plain "are you sure you want to delete this"
prompt). More constructors (e.g. for Posts) can be added here as that need
comes up.

`ConfirmServerDelete`/`ConfirmAccountDelete`/`ConfirmMediaDelete`/
`ConfirmMarkdownEditingDataLost` delegate their actual delete into a
Shared-owned submodel's own `DeleteConfirmed`/`CancelConfirmed`
(`AccountsPanel`/`MyMediaPanel`/`MarkdownPanel`) once confirmed, since those
submodels (unlike a page's own `Model`) are reachable from here.
`ConfirmMediaDelete`/`ConfirmMarkdownEditingDataLost` could in principle
follow the `ConfirmSyncSourceDelete`/`ConfirmPostDelete`/
`ConfirmEventDelete` shape below instead -- nothing about `MyMediaPanel`/
`MarkdownPanel` _requires_ living in `Shared.Model`, it's just simpler to
route through since they're already there (each _is_ a real global panel,
opened from several pages, unlike the old `Shared.SyncSourcesPanel` used
to be). `ConfirmServerDelete`/`ConfirmAccountDelete` genuinely can't switch:
removing a `Server`/`Account` has to mutate `AccountsPanel.Model` itself,
which only exists here.

`ConfirmMarkdownEditingDataLost` carries no payload (unlike
`ConfirmMediaDelete`'s `Media`) -- there's only ever one `MarkdownPanel`
instance, and what it'd discard is already sitting in
`Panels.markdownPanel.content` at confirm time, so there's nothing extra to
carry.

-}
type DeleteConfirmation
    = ConfirmServerDelete RellmServer
    | ConfirmAccountDelete RellmAccount
    | ConfirmMediaDelete Media
    | ConfirmMarkdownEditingDataLost
      -- The trailing `String` on each of these four is the acting
      -- `targetHost` (the source/Post/Event/User isn't itself paired with
      -- one) -- resolved back to a signed-in `Account` (if any) in
      -- `ConfirmDelete`'s own handling. Unlike every `DeleteConfirmation`
      -- above, none of these four are owned by a Shared-owned panel to
      -- delegate a `DeleteConfirmed` into -- each is a plain list (or, for
      -- `ConfirmUserDelete`, a single button) rendered by exactly one page
      -- (`Components.Pages.UserProfilePage`/`Pages.Post.PostId_`/
      -- `Pages.Event.PostId_`), so `ConfirmDelete` fires the delete RPC
      -- directly instead, and the result (`GotSyncSourceDeleteResult`/
      -- `GotPostDeleteResult`/`GotEventDeleteResult`/`GotUserDeleteResult`)
      -- is forwarded on to whichever page is active the same as any other
      -- `Shared.Msg`, for that page's own `Model` to apply. This is the
      -- shape any *new* "list of deletable things shown on one page" should
      -- follow -- don't give the list itself a Shared-owned home just to
      -- reach this dialog.
    | ConfirmSyncSourceDelete SyncSource Bool String
    | ConfirmPostDelete Post String
      -- `ConfirmPostDelete`'s counterpart for a Mastodon/Bluesky post, deleted as the connected account that wrote
      -- it (`Shared.Federation.Actions.deletePost`) -- the trailing `String` is its `"mastodon:" ++ instance` /
      -- `"bluesky:"` host. Fired from a reply card's Delete button on `Components.Mastodon.MastodonPostPage`/
      -- `BlueskyPostPage`.
    | ConfirmFederatedPostDelete Post String
    | ConfirmEventDelete Event String
      -- Deletes just `occasion` from `event` (every other `Occasion` is
      -- kept) rather than the whole `Event` -- `ConfirmDelete` fires
      -- `DeleteRemovedOccasions` with `event.occasions` minus `occasion`
      -- as the "keep" list, same "no Shared-owned home needed" shape as
      -- `ConfirmPostDelete`/`ConfirmEventDelete` above. Shown by
      -- `Pages.Event.PostId_`'s "Delete Occasion" button, next to "Delete
      -- Event", only once an `Event` has more than one `Occasion` (with
      -- exactly one, deleting it *is* deleting the Event -- see
      -- `backend/src/rpcs/events/get_events.rs`'s own `INNER JOIN`, which
      -- makes a zero-occasion Event unretrievable anyway).
    | ConfirmOccasionDelete Occasion Event String
      -- "New RSVP" on an anonymous RSVP (`Components.Rsvps`): starting over forgets the current
      -- private link, so it's confirmed first. Carries the occasion id and its acting `targetHost`;
      -- unlike the others, `ConfirmDelete` just reports back with `NewAnonymousRsvpConfirmed` and
      -- lets whichever page owns that RSVP form do the (purely local) reset.
    | ConfirmNewAnonymousRsvp String String
    | ConfirmUserDelete User String
      -- Un-syncs `instance` from the `SyncDestination` (`String`) whose
      -- display name is the trailing-but-one `String` (for the confirmation
      -- message only -- see `UI.deleteConfirmationModal`), acting on
      -- `targetHost` (the final `String`, mirroring the other three's own
      -- trailing host). Fired from a card's Delete button beside its "Push
      -- again" button (`Components.Events.eventSyncDestinationsView`'s
      -- `onDelete`) -- follows the same "list of deletable things shown on
      -- one page" shape as the four above: `ConfirmDelete` fires
      -- `DeleteOccasionSyncDestination` directly, and the result
      -- (`GotOccasionSyncDestinationDeleteResult`) is forwarded to
      -- whichever page is active the same as any other `Shared.Msg`.
    | ConfirmOccasionSyncDestinationDelete Occasion String String String
      -- `ConfirmOccasionSyncDestinationDelete`'s counterpart for a
      -- `Post` -- same shape (destination id, display name, acting host),
      -- just un-syncing `post` (`Components.Posts.deletePostSyncDestination`)
      -- instead of an `Occasion`. Fired from a card's Delete button
      -- beside its "Push again" button
      -- (`Components.Posts.postSyncDestinationsView`'s `onDelete`), on both
      -- `Components.Pages.PostPage`'s detail view and
      -- `Components.Pages.UserProfilePage`'s embedded `PostsPage` copy.
    | ConfirmPostSyncDestinationDelete Post String String String
      -- "Delete Phone"/"Delete Email" -- shown by both `Components.Pages.UserProfilePage.
      -- contactMethodDeleteButton` and `UI.contactMethodDeleteButton` (the ported copy in the
      -- Accounts Panel's own "Contact Methods" item), so it's not owned by either one specifically
      -- -- same "no Shared-owned home, `ConfirmDelete` fires the RPC directly" shape as the seven
      -- above, resolving the acting account from the carried `targetHost` (the trailing `String`,
      -- same convention). Carries the whole `ContactMethod` (not just its `value`) so
      -- `UI.deleteConfirmationModal` can warn -- via its own `verifiedAt` -- that deleting a
      -- *verified* one means re-verifying if it's ever added back. `ConfirmDelete`'s own handling
      -- `UpdateUser`s the field to `Nothing` outright (clearing value/visibility/verification/
      -- consent together, not just blanking `value`), same as the ported `Shared.Msg`s this
      -- replaces used to.
    | ConfirmPhoneDelete ContactMethod String
    | ConfirmEmailDelete ContactMethod String
      -- "Delete Link Preview Images" in `SettingsTab`'s Media Settings -- carries only the acting
      -- `targetHost`; same "no Shared-owned home, `ConfirmDelete` fires the RPC directly" shape as
      -- the others (`MediaMaintenance.deleteLinkPreviewImages`), reporting back with
      -- `GotLinkPreviewImagesDeleteResult`.
    | ConfirmDeleteLinkPreviewImages String


{-| Every app-wide "Panel" other than the Accounts Panel (see `Model.accounts`
for why that one stays its own top-level field) -- bundled together purely to
keep `Model` from being one flat list of 20-ish fields; nothing here actually
needs to reach across into a sibling panel's state (each `update` branch in
`sharedUpdate` still dispatches on exactly one of these at a time). See each
field's own module for what it holds. `confirmingDeleteFor` is included since
it's "effectively a Panel" from the UI's point of view -- see
`DeleteConfirmation`.
-}
type alias Panels =
    { federatedAuth : FederatedAuth.Model
    , starredPanel : StarredPanel.Model
    , markdownPanel : MarkdownPanel.Model
    , mediaGeneratorPanel : MediaGeneratorPanel.Model
    , mediaViewerPanel : MediaViewerPanel.Model
    , audioPlayerPanel : AudioPlayerPanel.Model
    , videoPlayerPanel : VideoPlayerPanel.Model
    , myMediaPanel : MyMediaPanel.Model
    , createNewPanel : CreateNewPanel.Model
    , messagingPanel : MessagingPanel.Model
    , confirmingDeleteFor : Maybe DeleteConfirmation
    }


{-| See `Model.pageSlide`.
-}
type PageSlide
    = PageSlideFromLeft
    | PageSlideFromRight


{-| The live scroll metrics of `.nav-links-scroll` (see `UI.headerNav`),
read off its `scroll` event (`UI.navLinksScrollDecoder`) -- drives the Home
link's (`.nav-link-home`, `UI.navLink`) scroll-triggered shrink animation.
See `navLinkHomeMaxWidth`, its one consumer.
-}
type alias NavAnimationState =
    { scrollLeft : Float
    , scrollWidth : Float
    , clientWidth : Float
    , homeCollapsed : Bool
    }


{-| `flags` is `{ state, systemPrefersDark, themePreference, timeZoneAbbreviation, uses24HourTime,
blueskyAccounts, mastodonAccountsAndServers, ... }` -- see `index.html`. `state` (the persisted
accounts/servers blob), `blueskyAccounts`, and `mastodonAccountsAndServers` are all handed to
`AccountsPanel.init` un-decoded, as three separate values (mirroring their three separate
`Ports.persist*` calls) -- appearance has its own, separate persisted key (`themePreference`) so
changing it doesn't need to know anything about `AccountsPanel`'s persisted shape, or vice versa.
`req.url` is assumed already-normalized (see `normalizeUrl`) -- `basePath` is passed alongside it only
because view code (see `UI.navLink`) needs it back to build hrefs.
-}
init : String -> Request -> Flags -> ( Model, Cmd Msg )
init basePath req flags =
    let
        accountsPanelFlags : Decode.Value
        accountsPanelFlags =
            Decode.decodeValue (Decode.field "state" Decode.value) flags
                |> Result.withDefault Encode.null

        starredPostsFlags : Decode.Value
        starredPostsFlags =
            Decode.decodeValue (Decode.field "starredPosts" Decode.value) flags
                |> Result.withDefault Encode.null

        federatedAuthFlags : Decode.Value
        federatedAuthFlags =
            Decode.decodeValue (Decode.field "federatedAuthKeyPair" Decode.value) flags
                |> Result.withDefault Encode.null

        userPreferencesFlags : Decode.Value
        userPreferencesFlags =
            Decode.decodeValue (Decode.field "userPreferences" Decode.value) flags
                |> Result.withDefault Encode.null

        blueskyAccountsFlags : Decode.Value
        blueskyAccountsFlags =
            Decode.decodeValue (Decode.field "blueskyAccounts" Decode.value) flags
                |> Result.withDefault Encode.null

        mastodonAccountsAndServersFlags : Decode.Value
        mastodonAccountsAndServersFlags =
            Decode.decodeValue (Decode.field "mastodonAccountsAndServers" Decode.value) flags
                |> Result.withDefault Encode.null

        systemPrefersDark : Bool
        systemPrefersDark =
            Decode.decodeValue (Decode.field "systemPrefersDark" Decode.bool) flags
                |> Result.withDefault False

        themePreference : ThemePreference
        themePreference =
            Decode.decodeValue (Decode.field "themePreference" Decode.string) flags
                |> Result.map themePreferenceFromString
                |> Result.withDefault ThemeAuto

        timeZoneAbbreviation : String
        timeZoneAbbreviation =
            Decode.decodeValue (Decode.field "timeZoneAbbreviation" Decode.string) flags
                |> Result.withDefault ""

        uses24HourTime : Bool
        uses24HourTime =
            Decode.decodeValue (Decode.field "uses24HourTime" Decode.bool) flags
                |> Result.withDefault False

        browser : BrowserInfo.Browser
        browser =
            Decode.decodeValue (Decode.field "userAgent" Decode.string) flags
                |> Result.map BrowserInfo.fromUserAgent
                |> Result.withDefault BrowserInfo.UnknownBrowser

        ( accountsPanelModel, accountsPanelCmd ) =
            AccountsPanel.init req accountsPanelFlags blueskyAccountsFlags mastodonAccountsAndServersFlags

        ( federatedAuthModel, federatedAuthCmd ) =
            FederatedAuth.init federatedAuthFlags

        model : Model
        model =
            { accounts = accountsPanelModel
            , panels =
                { federatedAuth = federatedAuthModel
                , starredPanel = StarredPanel.init starredPostsFlags
                , markdownPanel = MarkdownPanel.init
                , mediaGeneratorPanel = MediaGeneratorPanel.init
                , mediaViewerPanel = MediaViewerPanel.init
                , audioPlayerPanel =
                    let
                        player : AudioPlayerPanel.Model
                        player =
                            AudioPlayerPanel.init
                    in
                    -- A `#track-<id>` link: fetched once the server connects (see `trackLinkFetch`).
                    { player
                        | pendingTrackLink = AudioPlayerPanel.trackLinkFromFragment req.url.fragment
                        , pendingVideoLink = AudioPlayerPanel.videoLinkFromFragment req.url.fragment
                        , origin = originOf req.url
                    }
                , videoPlayerPanel = VideoPlayerPanel.init
                , myMediaPanel = MyMediaPanel.init
                , createNewPanel = CreateNewPanel.init
                , messagingPanel = MessagingPanel.init
                , confirmingDeleteFor = Nothing
                }
            , breadcrumbs = Breadcrumbs.init
            , countabilibar = Countabilibar.init
            , quoteLinks = QuoteLinks.init
            , postsCache = PostsCache.empty
            , eventsCache = EventsCache.empty
            , theme = { preference = themePreference, systemPrefersDark = systemPrefersDark }
            , userPreferences = UserPreferences.init userPreferencesFlags
            , basePath = basePath
            , browser = browser
            , scrollPreserverVisible = False
            , pageSlide = Nothing
            , navAnimationState =
                { scrollLeft = 0
                , scrollWidth = 0
                , clientWidth = 0
                , homeCollapsed = False
                }

            -- Corrected as soon as `getInitialWindowSizeCmd` resolves, below
            -- -- arbitrary until then, but never consulted before that (both
            -- panels start closed) so it doesn't matter what it is.
            , windowSize = { width = 0, height = 0 }

            -- `browserTimeZone.zone` is corrected as soon as `getBrowserZone`,
            -- below, resolves; `now` as soon as `Task.perform GotNow Time.now`
            -- does -- see `SharedTime.Model`'s own doc.
            , time =
                { browserTimeZone = { zone = Time.utc, name = "", abbreviation = timeZoneAbbreviation, uses24Hour = uses24HourTime }
                , now = Time.millisToPosix 0
                }
            , mediaRenderer = MediaRenderer.init
            }

        -- Already-connected Mastodon/Bluesky accounts' server-side stars, so starred posts show
        -- as starred everywhere straight away -- see `StarredPanel.refreshServerStars`.
        ( starredPanelWithServerStars, serverStarsCmd ) =
            StarredPanel.refreshServerStars accountsPanelModel model.panels.starredPanel

        panelsWithServerStars : Panels
        panelsWithServerStars =
            model.panels
    in
    ( { model | panels = { panelsWithServerStars | starredPanel = starredPanelWithServerStars } }
    , Cmd.batch
        [ Cmd.map StarredPanelMsg serverStarsCmd
        , Cmd.map AccountsPanelMsg accountsPanelCmd
        , Cmd.map FederatedAuthMsg federatedAuthCmd
        , Ports.setTheme (appliedTheme model)

        -- `mainFrontendHost`'s branding isn't fetched yet at this point, so
        -- this is only ever the neutral placeholder (see
        -- `UI.ServerTheme.neutralColorMeta`) -- matches `sharedUpdate`'s later
        -- calls once real branding loads via `navBarColorCmd`, rather than
        -- leaving the static light/dark `<meta>` values from `index.html` in
        -- place until then.
        , Ports.setNavBarColor (AccountsPanel.mainServerTheme (effectiveDarkMode model) model.accounts).primaryColor
        , getInitialWindowSizeCmd
        , Task.attempt
            (\result ->
                case result of
                    Ok ( name, zone ) ->
                        GotTimeZone name zone

                    Err _ ->
                        GotTimeZone "" Time.utc
            )
            getBrowserZone
        , Task.perform GotNow Time.now
        ]
    )


{-| Polls for still-missing starred posts (see `Shared.StarredPanel.kickOffFetches`)
only while the panel's actually open -- there's nothing to show for it
otherwise, so no reason to keep hitting servers in the background.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.systemPrefersDarkChanged SystemPrefersDarkChanged
        , Browser.Events.onResize WindowResized
        , Ports.pushNotificationClicked (Decode.decodeValue Decode.string >> Result.withDefault "" >> PushNotificationClicked)
        , Sub.map AccountsPanelMsg (AccountsPanel.subscriptions model.accounts)
        , Sub.map FederatedAuthMsg FederatedAuth.subscriptions
        , Sub.map StarredPanelMsg (StarredPanel.subscriptions model.panels.starredPanel)
        , Sub.map MediaViewerPanelMsg (MediaViewerPanel.subscriptions model.panels.mediaViewerPanel)

        -- The viewer pages with the same arrow keys -- while it's open (e.g. editing a track from the
        -- player) it gets them, not the player underneath.
        , if model.panels.mediaViewerPanel.currentMediaReference == Nothing then
            Sub.map AudioPlayerPanelMsg (AudioPlayerPanel.subscriptions model.panels.audioPlayerPanel)

          else
            Sub.none
        , Sub.map VideoPlayerPanelMsg VideoPlayerPanel.subscriptions
        , AudioPlayerPanel.handoffSubscription AudioHandoffRequested
        , Sub.map MyMediaPanelMsg (MyMediaPanel.subscriptions model.panels.myMediaPanel)
        , Sub.map MessagingPanelMsg (MessagingPanel.subscriptions model.panels.messagingPanel)
        , Sub.map MarkdownPanelMsg (MarkdownPanel.subscriptions model.panels.markdownPanel)
        , Sub.map CountabilibarMsg (Countabilibar.subscriptions model.countabilibar)
        , if model.panels.starredPanel.showStarredPanel && StarredPanel.hasPendingFetches model.panels.starredPanel then
            Time.every 1500 (\_ -> StarredPanelMsg StarredPanel.PollStarredPosts)

          else
            Sub.none
        ]


{-| Wraps `sharedUpdate` to also call out to `Ports.setNavBarColor` whenever
`mainFrontendHost`'s theme actually changes as a result of the message --
either `mainFrontendHost` itself changing (e.g. `AccountsPanel.SetMainFrontendHost`)
or its `Server`'s cached branding being (re)populated (e.g. after a
`ServerConfiguration` fetch). Comparing `primaryColor` before/after here,
rather than threading a "did the theme change" flag out of every branch that
touches `accountsPanel`, means every current and future such path gets this
for free.
-}
update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update req msg model =
    let
        ( newModel, cmd ) =
            sharedUpdate req msg model

        -- Cover art picking spans three panels (the audio player, the viewer's edit form and
        -- `Shared.MyMediaPanel`'s chooser), so its hand-offs are chained here -- see `coverArtFollowUp`.
        ( followedModel, followCmd ) =
            coverArtFollowUp req msg model newModel

        -- `#track-<id>` links, both ways: fetch a linked track once its server is connected, and mirror the
        -- player's expanded track into the URL.
        ( linkedModel, linkCmd ) =
            trackLinkFetch followedModel

        -- A link naming a server the user hasn't added gets a preview of it, for the prompt offering to add it (`UI`).
        ( previewedModel, previewCmd ) =
            linkServerPreview req linkedModel

        ( hashedModel, hashCmd ) =
            trackHashSync req model previewedModel

        -- Quotes waiting on a server (its preview connection landing, a server being added/enabled) get
        -- another look after every message -- see `QuoteLinks.advance`.
        ( quotedModel, quoteCmd ) =
            quoteLinksAdvance hashedModel

        -- A video the media viewer lands on plays in the video player panel (see `viewerVideoSync`).
        ( viewedModel, viewedCmd ) =
            viewerVideoSync req model (eventsCacheSync msg model (postsCacheSync msg model quotedModel))
    in
    case rootRedirectCmd req msg model of
        Just redirect ->
            -- Leaving the page anyway: skip the rest (notably hiding the splash, which would flash
            -- this soon-to-be-replaced page).
            ( viewedModel, Cmd.batch [ cmd, redirect ] )

        Nothing ->
            ( viewedModel, Cmd.batch [ cmd, viewedCmd, followCmd, linkCmd, previewCmd, hashCmd, quoteCmd, navBarColorCmd model newModel, themeCmd model newModel, splashHiddenCmd model newModel ] )


{-| Keeps `Shared.PostsCache` honest after every message (see its module doc): feeds fetched as an account
that is no longer the acting one on their server are dropped -- so signing out of (or switching, or disabling)
a server forgets its cached posts right then -- along with "Following" snapshots whenever the signed-in
accounts changed at all; a post being deleted drops the snapshots showing it (at the moment the deletion is
confirmed), and creating one on a server those with posts from it.
-}
postsCacheSync : Msg -> Model -> Model -> Model
postsCacheSync msg before after =
    let
        evicted : PostsCache.Model
        evicted =
            case ( msg, before.panels.confirmingDeleteFor ) of
                ( ConfirmDelete, Just (ConfirmPostDelete post host) ) ->
                    PostsCache.evictPost host post.id after.postsCache

                ( ConfirmDelete, Just (ConfirmFederatedPostDelete post host) ) ->
                    PostsCache.evictPost host post.id after.postsCache

                ( CreateNewPanelMsg (CreateNewPanel.GotSaveResult (Ok ( _, CreateNewPanel.CreatedPost host _ ))), _ ) ->
                    PostsCache.evictHost host after.postsCache

                _ ->
                    after.postsCache
    in
    { after
        | postsCache =
            PostsCache.reconcile
                (\host -> RellmAccounts.enabledRellmAccountForServer after.accounts.accounts host |> Maybe.map RellmAccounts.rellmAccountId)
                (accountSignature before /= accountSignature after)
                evicted
    }


{-| `postsCacheSync`'s counterpart for `Shared.EventsCache`: feeds fetched as an account that is no longer the
acting one on their server are dropped; deleting an event (or one of its occasions) drops the snapshots showing
it once the deletion is confirmed, and creating one on a server those with events from it.
-}
eventsCacheSync : Msg -> Model -> Model -> Model
eventsCacheSync msg before after =
    let
        evicted : EventsCache.Model
        evicted =
            case ( msg, before.panels.confirmingDeleteFor ) of
                ( ConfirmDelete, Just (ConfirmEventDelete event host) ) ->
                    EventsCache.evictEvent host (event.post |> Maybe.map .id |> Maybe.withDefault "") after.eventsCache

                ( ConfirmDelete, Just (ConfirmOccasionDelete _ _ host) ) ->
                    EventsCache.evictHost host after.eventsCache

                ( CreateNewPanelMsg (CreateNewPanel.GotSaveResult (Ok ( _, CreateNewPanel.CreatedEvent host _ ))), _ ) ->
                    EventsCache.evictHost host after.eventsCache

                _ ->
                    after.eventsCache
    in
    { after
        | eventsCache =
            EventsCache.reconcile
                (\host -> RellmAccounts.enabledRellmAccountForServer after.accounts.accounts host |> Maybe.map RellmAccounts.rellmAccountId)
                evicted
    }


{-| Which accounts are signed in where, as comparable text -- changes exactly when the acting accounts do.
-}
accountSignature : Model -> List String
accountSignature model =
    List.map
        (\account ->
            RellmAccounts.rellmAccountId account
                ++ (if account.enabled then
                        "+"

                    else
                        "-"
                   )
        )
        model.accounts.accounts
        ++ List.map (\account -> "mastodon:" ++ account.instanceHost ++ ":" ++ account.username) model.accounts.mastodonAccounts
        ++ List.map
            (\account ->
                "bluesky:"
                    ++ account.handle
                    ++ (if account.enabled then
                            "+"

                        else
                            "-"
                       )
            )
            model.accounts.blueskyAccounts


{-| The media viewer doesn't play videos itself: when it opens on one, or pages to one, that video becomes the queue's
current entry (`OpenVideo` -- the existing queue follows it, like anything played from somewhere), and
`Shared.VideoPlayerPanel`'s player glides over the viewer's stage (`public/rellm-video.js`) with its controls. A video the
viewer is *still* showing isn't started again, whatever else the queue has since moved on to. A thumbnail's enlarge button
leaves its position for the panel's player to continue from (`public/rellm-media.js`), so playback carries on.
-}
viewerVideoSync : Request -> Model -> Model -> ( Model, Cmd Msg )
viewerVideoSync req before after =
    let
        viewing : Model -> Maybe MediaViewerPanel.ViewerVideo
        viewing model =
            MediaViewerPanel.currentVideo model.accounts model.panels.mediaViewerPanel
    in
    case viewing after of
        Just video ->
            if Maybe.map .mediaId (viewing before) == Just video.mediaId then
                ( after, Cmd.none )

            else
                sharedUpdate req
                    (AudioPlayerPanelMsg
                        (AudioPlayerPanel.OpenViewerVideo
                            -- (The miniplayer's enlarge button hands the viewer just a URL: the queue's entry for the same video keeps its link and downloads.)
                            (AudioPlayerPanel.inheritLinkData after.panels.audioPlayerPanel
                                { src = video.src
                                , poster = video.poster
                                , aspectRatio = video.aspectRatio
                                , returnUrl = Url.toString req.url
                                , mediaId = Just video.mediaId
                                , host = video.host
                                , downloads = video.downloads
                                , postUrl = Nothing
                                }
                            )
                            (Just video.title)
                            0
                            video.autoplay
                            (viewing before == Nothing)
                        )
                    )
                    after

        Nothing ->
            -- Paged from a video to something else (an image) with the viewer still open: the miniplayer closes -- the video doesn't
            -- carry on in the corner -- and a video that was current before the viewer took over comes back, paused. (Closing the
            -- viewer on the video, or its shrink button, are what hand it to the miniplayer.)
            case ( viewing before, after.panels.mediaViewerPanel.currentMediaReference ) of
                ( Just left, Just _ ) ->
                    if Maybe.andThen (\current -> current.video.mediaId) (AudioPlayerPanel.currentVideo after.panels.audioPlayerPanel) == Just left.mediaId then
                        sharedUpdate req (AudioPlayerPanelMsg AudioPlayerPanel.LeaveViewerVideo) after

                    else
                        ( after, Cmd.none )

                _ ->
                    ( after, Cmd.none )


{-| `QuoteLinks.advance` against the current accounts -- see its own doc.
-}
quoteLinksAdvance : Model -> ( Model, Cmd Msg )
quoteLinksAdvance model =
    let
        ( quoteLinks, cmd ) =
            QuoteLinks.advance model.accounts model.quoteLinks
    in
    ( { model | quoteLinks = quoteLinks }, Cmd.map QuoteLinksMsg cmd )


{-| `scheme://host[:port]` of `url` -- what a shared link to a track starts with.
-}
originOf : Url -> String
originOf url =
    Url.toString { url | path = "", query = Nothing, fragment = Nothing }


setVideoPanel : (VideoPlayerPanel.Model -> VideoPlayerPanel.Model) -> Model -> Model
setVideoPanel change model =
    let
        panels : Panels
        panels =
            model.panels
    in
    { model | panels = { panels | videoPlayerPanel = change panels.videoPlayerPanel } }


{-| Keeps the miniplayer showing the queue's current entry: when that's a video (newly, or begun again -- `generation`) it's
shown, starting where the queue says; when it isn't, the miniplayer is hidden.
-}
syncVideoPanel : AudioPlayerPanel.Model -> AudioPlayerPanel.Model -> VideoPlayerPanel.Model -> VideoPlayerPanel.Model
syncVideoPanel before after panel =
    case AudioPlayerPanel.currentVideo after of
        Nothing ->
            VideoPlayerPanel.update VideoPlayerPanel.Hide panel

        Just current ->
            if Maybe.map .generation (AudioPlayerPanel.currentVideo before) == Just current.generation then
                panel

            else
                VideoPlayerPanel.update
                    (VideoPlayerPanel.Show
                        { src = current.video.src
                        , poster = current.video.poster
                        , title = Just current.title
                        , startAt = current.startAt
                        , resume = current.resume
                        , aspectRatio = current.video.aspectRatio
                        , returnUrl = current.video.returnUrl
                        , mediaId = current.video.mediaId
                        , host = current.video.host
                        , downloads = current.video.downloads
                        , postUrl = current.video.postUrl
                        }
                    )
                    panel


{-| `GetMedia` for track `id` on `host` (an enabled account there is used, if there is one), whose result goes to `toMsg`.
-}
fetchTrack : Model -> String -> String -> (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ) -> Msg) -> Cmd Msg
fetchTrack model host id toMsg =
    AccountsPanel.performWithOptionalAccountServer
        model.accounts
        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
        (\server maybeToken ->
            Grpc.new Rellm.getMedia { defaultGetMediaRequest | mediaId = Just id }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )
        |> Task.attempt toMsg


{-| Starts fetching the track (or video) a `#track-<id>` / `#video-<id>` link (`AudioPlayerPanel.Model.pendingTrackLink` /
`pendingVideoLink`) points at, as soon as its server is connected -- tried after every `Shared` message, like the media
pages' own `retryFetch`, since at startup the server is usually still connecting. The result arrives as `GotLinkedTrack` /
`GotLinkedVideo`.
-}
trackLinkFetch : Model -> ( Model, Cmd Msg )
trackLinkFetch model =
    let
        panels : Panels
        panels =
            model.panels

        player : AudioPlayerPanel.Model
        player =
            panels.audioPlayerPanel

        -- A federated link (`#track-<id>@<host>`) names the server the media lives on.
        hostOf : AudioPlayerPanel.TrackLink -> String
        hostOf link =
            Maybe.withDefault model.accounts.mainFrontendHost link.host

        ready : AudioPlayerPanel.TrackLink -> Bool
        ready link =
            RellmServers.knownConnectedRellmServer model.accounts.servers (hostOf link) /= Nothing
    in
    case ( player.pendingTrackLink, player.pendingVideoLink ) of
        ( Just link, _ ) ->
            if ready link then
                ( { model | panels = { panels | audioPlayerPanel = { player | pendingTrackLink = Nothing } } }
                , fetchTrack model (hostOf link) link.id (GotLinkedTrack (hostOf link) player.selectionGeneration)
                )

            else
                ( model, Cmd.none )

        ( Nothing, Just link ) ->
            if ready link then
                ( { model | panels = { panels | audioPlayerPanel = { player | pendingVideoLink = Nothing } } }
                , fetchTrack model (hostOf link) link.id (GotLinkedVideo (hostOf link) player.selectionGeneration)
                )

            else
                ( model, Cmd.none )

        ( Nothing, Nothing ) ->
            ( model, Cmd.none )


{-| A `#track-<id>@<host>` / `#video-<id>@<host>` link to a server the user hasn't added: asks `AccountsPanel` for the anonymous
preview connection it makes for any server it shows but the user doesn't have (its name and logo, for the "Add" button in `UI`'s
link prompt) -- only for hosts that look like a public domain name (`RellmLinks.isProbeableHost`), as for quoted links, and once
per host (the preview is seeded the moment it's asked for). Nothing is added or connected without the user pressing that button.
-}
linkServerPreview : Request -> Model -> ( Model, Cmd Msg )
linkServerPreview req model =
    case AudioPlayerPanel.pendingLink model.panels.audioPlayerPanel |> Maybe.andThen (Tuple.second >> .host) of
        Just host ->
            if
                (RellmServers.rellmServerForHost model.accounts.servers host == Nothing)
                    && RellmLinks.isProbeableHost host
                    && not (Dict.member host model.accounts.recommendedServerConnections)
            then
                sharedUpdate req (AccountsPanelMsg (AccountsPanel.EnsureServerPreviews [ host ])) model

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Keeps the URL fragment in step with the audio player: expanding it sets `#track-<id>` (remembering whatever
fragment was there), moving to another track while expanded updates it, and collapsing -- or closing the player --
puts the remembered fragment back. Done with `replaceUrl`, so it doesn't fill the history. Only reverts a fragment
that is still one of ours. `before`/`after` are the models around one `update`; a viewer that merely forces the player
collapsed doesn't count (that doesn't touch `expanded`).
-}
trackHashSync : Request -> Model -> Model -> ( Model, Cmd Msg )
trackHashSync req before after =
    let
        panels : Panels
        panels =
            after.panels

        old : AudioPlayerPanel.Model
        old =
            before.panels.audioPlayerPanel

        player : AudioPlayerPanel.Model
        player =
            panels.audioPlayerPanel

        -- The fragment linking to the current entry: `track-<id>` for a track, `video-<id>` for a video on one of our
        -- servers; a video that is just a URL has none, so it never counts.
        fragmentOf : AudioPlayerPanel.Model -> Maybe String
        fragmentOf model =
            if model.expanded then
                AudioPlayerPanel.linkFragment after.accounts.mainFrontendHost model

            else
                Nothing

        wasOn : Bool
        wasOn =
            fragmentOf old /= Nothing

        isOn : Bool
        isOn =
            fragmentOf player /= Nothing

        replaceFragment : Maybe String -> Cmd Msg
        replaceFragment fragment =
            let
                url : Url
                url =
                    req.url
            in
            if fragment == url.fragment then
                Cmd.none

            else
                let
                    fullPath : String
                    fullPath =
                        if after.basePath == "" then
                            url.path

                        else if url.path == "/" then
                            after.basePath ++ "/"

                        else
                            after.basePath ++ url.path
                in
                Nav.replaceUrl req.key (Url.toString { url | path = fullPath, fragment = fragment })

        withSaved : Maybe (Maybe String) -> Model
        withSaved saved =
            { after | panels = { panels | audioPlayerPanel = { player | savedFragment = saved } } }
    in
    case ( wasOn, isOn, fragmentOf player ) of
        ( False, True, Just fragment ) ->
            -- Remember what was there (unless it's already one of our links, e.g. we got here from one).
            ( withSaved
                (Just
                    (if AudioPlayerPanel.isLinkFragment req.url.fragment then
                        Nothing

                     else
                        req.url.fragment
                    )
                )
            , replaceFragment (Just fragment)
            )

        ( True, True, Just fragment ) ->
            if fragmentOf old /= Just fragment then
                ( after, replaceFragment (Just fragment) )

            else
                ( after, Cmd.none )

        ( True, False, _ ) ->
            if AudioPlayerPanel.isLinkFragment req.url.fragment then
                ( withSaved Nothing, replaceFragment (old.savedFragment |> Maybe.withDefault Nothing) )

            else
                ( withSaved Nothing, Cmd.none )

        _ ->
            ( after, Cmd.none )


{-| When the app is being served at `/elm` but `browsingHost`'s own freshly-fetched
`ServerConfiguration` (`GotMainServerResult`'s `Ok` -- never a persisted/cached one, which could be
stale) says its default web UI is this Elm app, `location.replace`s to the same path/query/fragment at
the root, where the backend serves it too (see `ElmSpaAtRoot` in `backend/src/web/elm_web.rs`, which
gates on the same setting). Skipped when the config belongs to a different host than we're browsing
(`resolvedFrontendHost` -- the CDN-backend case), and for `/elm/auth/*` and the OAuth callback, which
are mid-flow and must finish where they started.
-}
rootRedirectCmd : Request -> Msg -> Model -> Maybe (Cmd Msg)
rootRedirectCmd req msg model =
    case msg of
        AccountsPanelMsg (AccountsPanel.GotMainServerResult (Ok ( _, config ))) ->
            let
                -- `req.url` is already normalized (`basePath` stripped -- see `normalizeUrl`), so this is the
                -- page's path as it'd be served from the root: exactly where to redirect to. (It used to
                -- strip four more characters off it, as if it still began with "/elm" -- turning
                -- `/elm/about` into `/ut`, and the `/elm/auth/` exemption below could never match.)
                path : String
                path =
                    req.url.path

                isElmUi : Bool
                isElmUi =
                    (config.serverInfo |> Maybe.andThen .webUserInterface) == Just ELMSPA

                exempt : Bool
                exempt =
                    String.startsWith "/auth/" path || path == "/oauth-callback.html"
            in
            if
                model.basePath
                    == "/elm"
                    && isElmUi
                    && not exempt
                    && RellmServers.resolvedFrontendHost model.accounts.browsingHost config
                    == model.accounts.browsingHost
            then
                Just
                    (Ports.replaceLocation
                        (path
                            ++ (req.url.query |> Maybe.map ((++) "?") |> Maybe.withDefault "")
                            ++ (req.url.fragment |> Maybe.map ((++) "#") |> Maybe.withDefault "")
                        )
                    )

            else
                Nothing

        _ ->
            Nothing


{-| Follow-on messages between the audio player, the viewer and the media chooser, dispatched after
`sharedUpdate` has handled `msg` itself:

  - a saved edit in the viewer refreshes the player's copy of the track;
  - the viewer starting to choose cover art (`MediaViewerPanel.ChooseCoverArtClicked`) opens `Shared.MyMediaPanel` as a single-image chooser;
  - the chooser then reports its pick (or a cancel), which goes back to the viewer -- gated on the viewer
    actually waiting for one, so an unrelated media pick/close elsewhere is never mistaken for it.

-}
coverArtFollowUp : Request -> Msg -> Model -> Model -> ( Model, Cmd Msg )
coverArtFollowUp req msg oldModel newModel =
    let
        chain : Msg -> ( Model, Cmd Msg )
        chain next =
            sharedUpdate req next newModel
    in
    case msg of
        -- An edit saved in the viewer: the audio player keeps its own copy of the queue -- refresh it.
        MediaViewerPanelMsg (MediaViewerPanel.GotEditSaveResult _ (Ok ( _, updated ))) ->
            chain (AudioPlayerPanelMsg (AudioPlayerPanel.MediaUpdated (MediaViewerPanel.mediaToReference updated)))

        MediaViewerPanelMsg MediaViewerPanel.ChooseCoverArtClicked ->
            chain
                (MyMediaPanelMsg
                    (MyMediaPanel.Open
                        (Just (MyMediaPanel.SingleSelect { imagesOnly = True, initialSelection = Nothing }))
                        newModel.panels.mediaViewerPanel.targetHost
                    )
                )

        MyMediaPanelMsg (MyMediaPanel.MediaItemClicked mediaId) ->
            if oldModel.panels.mediaViewerPanel.choosingCoverArt then
                chain (MediaViewerPanelMsg (MediaViewerPanel.CoverArtChosen mediaId))

            else
                ( newModel, Cmd.none )

        MyMediaPanelMsg MyMediaPanel.CloseClicked ->
            if oldModel.panels.mediaViewerPanel.choosingCoverArt then
                chain (MediaViewerPanelMsg MediaViewerPanel.CoverArtChooserClosed)

            else
                ( newModel, Cmd.none )

        _ ->
            ( newModel, Cmd.none )


{-| Whether `msg` is a page reporting what it's showing to `Shared.Countabilibar` (see
`CountabilibarSync`) -- as opposed to an echo of a message that was just delivered to it. `Main` and
`Pages.Home_` drop the latter from a page's effects (see `Main.notifyPageOfSharedMsg`) but must keep
these: a page updated by a forwarded message (e.g. a server just disabled) may have changed what it
shows with no later update of its own to report it.
-}
isCountabilibarSync : Msg -> Bool
isCountabilibarSync msg =
    case msg of
        CountabilibarSync _ ->
            True

        _ ->
            False


{-| Whether pages need to hear about `msg` (via their own `fromShared`, see `Main.notifyPageOfSharedMsg`).
Not for anything `Shared.Countabilibar` does on its own account -- counts (a page's own, reported
back at it), animation ticks and the popover opening -- only for what changes which servers/users
are hidden, which pages have to react to.
-}
notifiesPages : Msg -> Bool
notifiesPages msg =
    case msg of
        CountabilibarSync _ ->
            False

        PostsCacheMsg _ ->
            False

        EventsCacheMsg _ ->
            False

        CountabilibarMsg countabilibarMsg ->
            Countabilibar.affectsPages countabilibarMsg

        _ ->
            True


closeCountabilibarPanel : Model -> ( Model, Cmd Msg )
closeCountabilibarPanel model =
    ( { model | countabilibar = Countabilibar.closePanel model.countabilibar }, Cmd.none )


sharedUpdate : Request -> Msg -> Model -> ( Model, Cmd Msg )
sharedUpdate req msg model =
    case msg of
        AccountsPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd ) =
                    AccountsPanel.update req subMsg model.accounts

                changedHosts : List String
                changedHosts =
                    starredPostsRefreshHosts model.accounts subModel

                ( hostRefreshedStarredPanel, hostRefreshCmd ) =
                    StarredPanel.refreshHosts subModel changedHosts panels.starredPanel

                -- Connecting/disconnecting/switching a Mastodon/Bluesky account changes whose
                -- server-side stars apply -- see `StarredPanel.refreshServerStars`.
                ( refreshedStarredPanel, serverStarsCmd ) =
                    StarredPanel.refreshServerStars subModel hostRefreshedStarredPanel

                refreshCmd : Cmd StarredPanel.Msg
                refreshCmd =
                    Cmd.batch [ hostRefreshCmd, serverStarsCmd ]

                -- Mirrors `Pages.Messages`' own `SharedMsg (Shared.AccountsPanelMsg
                -- _)` handling (`applyPageMsg shared MessagesPage.Poll model`) --
                -- unconditional on every `AccountsPanelMsg`, not just
                -- `ServerConnected`, since `Poll`'s own `fetchNewServers` only
                -- ever (re)fetches an entry that's newly eligible or changed
                -- account/listingType, so this is a no-op RPC-wise whenever
                -- nothing relevant actually changed. Without this, the nav
                -- badge (`UI.elm`'s `MessagingPanel.totalUnreadCount`) stayed
                -- at 0 until the user opened the Messages panel at least once
                -- this session -- `Shared.MessagingPanel.init`'s own `empty`
                -- deliberately fetches nothing up front, see its doc -- even
                -- though the servers/accounts it'd need were already bootstrapped
                -- by `AccountsPanel` well before that.
                ( polledMessagingPanel, pollMessagingCmd ) =
                    let
                        ( m, cmd, _ ) =
                            MessagingPanel.update subModel (MessagingPanel.PageMsg MessagesPage.Poll) panels.messagingPanel
                    in
                    ( m, cmd )

                -- The Accounts Panel and Starred Panel are both
                -- full-width slide-out panels on narrow screens (see
                -- `UI.Responsive`), so opening one closes the other there.
                shouldCloseStarredPanel : Bool
                shouldCloseStarredPanel =
                    case subMsg of
                        AccountsPanel.ToggleAccountsPanel ->
                            subModel.showAccountsPanel && Responsive.isNarrow model.windowSize

                        _ ->
                            False

                ( closedStarredPanel, closeCmd ) =
                    if shouldCloseStarredPanel then
                        let
                            ( closedModel, cmd, _ ) =
                                StarredPanel.update subModel StarredPanel.CloseStarredPanel refreshedStarredPanel
                        in
                        ( closedModel, cmd )

                    else
                        ( refreshedStarredPanel, Cmd.none )

                -- Unlike `shouldCloseStarredPanel` above, unconditional --
                -- not just narrow screens -- since the New Post/Event panel
                -- opens at this same vertical position (see
                -- create_new_panel.css's own `top` comment) rather than as
                -- one of `.navbar`'s own dropdowns, so the two would
                -- visually collide at any width. Mirrors `CreateNewPanelMsg`'s
                -- own `shouldCloseAccountsPanel`, in the other direction.
                shouldCloseCreateNewPanel : Bool
                shouldCloseCreateNewPanel =
                    case subMsg of
                        AccountsPanel.ToggleAccountsPanel ->
                            subModel.showAccountsPanel

                        _ ->
                            False

                ( closedCreateNewPanel, closeCreateNewCmd ) =
                    if shouldCloseCreateNewPanel then
                        let
                            ( m, cmd, _ ) =
                                CreateNewPanel.update model.time.browserTimeZone model.time.now subModel CreateNewPanel.CloseClicked panels.createNewPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.createNewPanel, Cmd.none )

                -- Mirrors `shouldCloseStarredPanel` above -- the Messaging
                -- panel is another `.navbar`-anchored dropdown, same
                -- narrow-screen collision with the Accounts Panel.
                shouldCloseMessagingPanel : Bool
                shouldCloseMessagingPanel =
                    case subMsg of
                        AccountsPanel.ToggleAccountsPanel ->
                            subModel.showAccountsPanel && Responsive.isNarrow model.windowSize

                        _ ->
                            False

                ( closedMessagingPanel, closeMessagingCmd ) =
                    if shouldCloseMessagingPanel then
                        let
                            ( m, cmd, _ ) =
                                MessagingPanel.update subModel MessagingPanel.CloseMessagingPanel polledMessagingPanel
                        in
                        ( m, cmd )

                    else
                        ( polledMessagingPanel, Cmd.none )
            in
            ( { model
                | accounts = subModel
                , panels = { panels | starredPanel = closedStarredPanel, createNewPanel = closedCreateNewPanel, messagingPanel = closedMessagingPanel }
              }
            , Cmd.batch
                [ Cmd.map AccountsPanelMsg subCmd
                , Cmd.map StarredPanelMsg refreshCmd
                , Cmd.map StarredPanelMsg closeCmd
                , Cmd.map MessagingPanelMsg pollMessagingCmd
                , Cmd.map CreateNewPanelMsg closeCreateNewCmd
                , Cmd.map MessagingPanelMsg closeMessagingCmd
                ]
            )

        FederatedAuthMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd ) =
                    FederatedAuth.update subMsg panels.federatedAuth
            in
            ( { model | panels = { panels | federatedAuth = subModel } }, Cmd.map FederatedAuthMsg subCmd )

        StarredPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd, ( maybeAccountsPanelMsg, maybeMediaViewerPanelMsg, maybeMediaRendererMsg ) ) =
                    StarredPanel.update model.accounts subMsg panels.starredPanel

                newMediaRenderer : MediaRenderer.Model
                newMediaRenderer =
                    case maybeMediaRendererMsg of
                        Just mediaRendererMsg ->
                            MediaRenderer.update mediaRendererMsg model.mediaRenderer

                        Nothing ->
                            model.mediaRenderer

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                ( mediaViewerPanelModel, mediaViewerPanelCmd, maybeMediaViewerAccountsPanelMsg ) =
                    case maybeMediaViewerPanelMsg of
                        Just mediaViewerPanelMsg ->
                            MediaViewerPanel.update model.accounts mediaViewerPanelMsg panels.mediaViewerPanel

                        Nothing ->
                            ( panels.mediaViewerPanel, Cmd.none, Nothing )

                -- Mirrors `AccountsPanelMsg`'s own close-the-other-panel
                -- branch, above -- see `UI.Responsive`.
                shouldCloseAccountsPanel : Bool
                shouldCloseAccountsPanel =
                    case subMsg of
                        StarredPanel.ToggleStarredPanel ->
                            subModel.showStarredPanel && Responsive.isNarrow model.windowSize

                        _ ->
                            False

                ( closedAccountsPanelModel, closeCmd ) =
                    if shouldCloseAccountsPanel then
                        AccountsPanel.update req AccountsPanel.CloseAccountsPanel accountsPanelModel

                    else
                        ( accountsPanelModel, Cmd.none )

                -- `MediaViewerPanel.update`'s own account-refresh, if any (only ever fires from an
                -- edit action -- `Open`, all this forwarding channel ever carries, never triggers
                -- one -- but handled uniformly regardless), layered on top of the above so neither
                -- refresh gets lost if both somehow fired in the same update.
                ( finalAccountsPanelModel, mediaViewerAccountsCmd ) =
                    case maybeMediaViewerAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg closedAccountsPanelModel

                        Nothing ->
                            ( closedAccountsPanelModel, Cmd.none )

                -- Unlike `shouldCloseAccountsPanel` above, unconditional --
                -- not just narrow screens -- since the New Post panel opens
                -- at this same vertical position (see
                -- create_new_panel.css's own `top` comment) rather than as
                -- one of `.navbar`'s own dropdowns, so the two would visually
                -- collide at any width.
                shouldCloseCreateNewPanel : Bool
                shouldCloseCreateNewPanel =
                    case subMsg of
                        StarredPanel.ToggleStarredPanel ->
                            subModel.showStarredPanel

                        _ ->
                            False

                ( closedCreateNewPanelModel, closeCreateNewCmd ) =
                    if shouldCloseCreateNewPanel then
                        let
                            ( m, cmd, _ ) =
                                CreateNewPanel.update model.time.browserTimeZone model.time.now finalAccountsPanelModel CreateNewPanel.CloseClicked panels.createNewPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.createNewPanel, Cmd.none )

                -- Both the Starred and Messaging panels are `.navbar`-anchored
                -- dropdowns at the same position, so opening one closes the
                -- other outright (not just narrow screens).
                shouldCloseMessagingPanel : Bool
                shouldCloseMessagingPanel =
                    case subMsg of
                        StarredPanel.ToggleStarredPanel ->
                            subModel.showStarredPanel

                        _ ->
                            False

                ( closedMessagingPanelModel, closeMessagingCmd ) =
                    if shouldCloseMessagingPanel then
                        let
                            ( m, cmd, _ ) =
                                MessagingPanel.update finalAccountsPanelModel MessagingPanel.CloseMessagingPanel panels.messagingPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.messagingPanel, Cmd.none )
            in
            ( { model
                | accounts = finalAccountsPanelModel
                , panels =
                    { panels
                        | starredPanel = subModel
                        , mediaViewerPanel = mediaViewerPanelModel
                        , createNewPanel = closedCreateNewPanelModel
                        , messagingPanel = closedMessagingPanelModel
                    }
                , mediaRenderer = newMediaRenderer
              }
            , Cmd.batch
                [ Cmd.map StarredPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , Cmd.map AccountsPanelMsg closeCmd
                , Cmd.map AccountsPanelMsg mediaViewerAccountsCmd
                , Cmd.map CreateNewPanelMsg closeCreateNewCmd
                , Cmd.map MessagingPanelMsg closeMessagingCmd
                , Cmd.map MediaViewerPanelMsg mediaViewerPanelCmd
                ]
            )

        UserPreferencesMsg subMsg ->
            let
                ( subModel, subCmd ) =
                    UserPreferences.update subMsg model.userPreferences
            in
            ( { model | userPreferences = subModel }, Cmd.map UserPreferencesMsg subCmd )

        MediaViewerPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd, maybeAccountsPanelMsg ) =
                    MediaViewerPanel.update model.accounts subMsg panels.mediaViewerPanel

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel, panels = { panels | mediaViewerPanel = subModel } }
            , Cmd.batch
                [ Cmd.map MediaViewerPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                ]
            )

        TrackLinkChanged fragment ->
            let
                panels : Panels
                panels =
                    model.panels

                player : AudioPlayerPanel.Model
                player =
                    panels.audioPlayerPanel
            in
            case ( AudioPlayerPanel.trackLinkFromFragment fragment, AudioPlayerPanel.videoLinkFromFragment fragment ) of
                -- Our own `replaceUrl` after expanding/changing track echoes back here: nothing to do.
                ( Just link, _ ) ->
                    if player.currentId == Just link.id && player.targetHost == Maybe.withDefault model.accounts.mainFrontendHost link.host then
                        ( model, Cmd.none )

                    else
                        ( { model | panels = { panels | audioPlayerPanel = { player | pendingTrackLink = Just link } } }, Cmd.none )

                ( Nothing, Just link ) ->
                    if AudioPlayerPanel.linkFragment model.accounts.mainFrontendHost player == fragment then
                        ( model, Cmd.none )

                    else
                        ( { model | panels = { panels | audioPlayerPanel = { player | pendingVideoLink = Just link } } }, Cmd.none )

                ( Nothing, Nothing ) ->
                    ( model, Cmd.none )

        -- A `#video-<id>` link's media arrived: it becomes the (paused) current video in the expanded player.
        GotLinkedVideo host generation result ->
            case result of
                Ok ( maybeAccountsPanelMsg, response ) ->
                    let
                        ( accountsPanelModel, accountsPanelCmd ) =
                            case maybeAccountsPanelMsg of
                                Just accountsPanelMsg ->
                                    AccountsPanel.update req accountsPanelMsg model.accounts

                                Nothing ->
                                    ( model.accounts, Cmd.none )

                        withAccounts : Model
                        withAccounts =
                            { model | accounts = accountsPanelModel }
                    in
                    case
                        response.media
                            |> List.head
                            |> Maybe.andThen (\media -> MediaViewerPanel.videoSource accountsPanelModel host (MediaViewerPanel.mediaToReference media))
                            -- (Likewise a stale reply opens nothing.)
                            |> Maybe.andThen (\video -> if generation == model.panels.audioPlayerPanel.selectionGeneration then Just video else Nothing)
                    of
                        Just video ->
                            let
                                ( loaded, loadCmd ) =
                                    sharedUpdate req
                                        (AudioPlayerPanelMsg
                                            (AudioPlayerPanel.LoadVideo
                                                { src = video.src
                                                , poster = video.poster
                                                , aspectRatio = video.aspectRatio
                                                , returnUrl = Url.toString req.url
                                                , mediaId = Just video.mediaId
                                                , host = video.host
                                                , downloads = video.downloads
                                                , postUrl = Nothing
                                                }
                                                (Just video.title)
                                            )
                                        )
                                        withAccounts
                            in
                            ( loaded, Cmd.batch [ Cmd.map AccountsPanelMsg accountsPanelCmd, loadCmd ] )

                        -- Not a video (or not ours to open), missing, private or unreachable: the link just doesn't open anything.
                        Nothing ->
                            ( withAccounts, Cmd.map AccountsPanelMsg accountsPanelCmd )

                Err _ ->
                    ( model, Cmd.none )

        GotLinkedTrack host generation result ->
            case result of
                Ok ( maybeAccountsPanelMsg, response ) ->
                    let
                        ( accountsPanelModel, accountsPanelCmd ) =
                            case maybeAccountsPanelMsg of
                                Just accountsPanelMsg ->
                                    AccountsPanel.update req accountsPanelMsg model.accounts

                                Nothing ->
                                    ( model.accounts, Cmd.none )

                        withAccounts : Model
                        withAccounts =
                            { model | accounts = accountsPanelModel }
                    in
                    case
                        response.media
                            |> List.head
                            -- (A reply for a link the user has since moved on from -- another track chosen, the player closed -- opens nothing.)
                            |> Maybe.andThen (\media -> if generation == model.panels.audioPlayerPanel.selectionGeneration then Just media else Nothing)
                    of
                        Just media ->
                            let
                                ( loaded, loadCmd ) =
                                    sharedUpdate req
                                        (AudioPlayerPanelMsg
                                            (AudioPlayerPanel.Load
                                                [ MediaViewerPanel.mediaToReference media ]
                                                media.id
                                                host
                                            )
                                        )
                                        withAccounts
                            in
                            ( loaded, Cmd.batch [ Cmd.map AccountsPanelMsg accountsPanelCmd, loadCmd ] )

                        Nothing ->
                            ( withAccounts, Cmd.map AccountsPanelMsg accountsPanelCmd )

                -- Missing, private or unreachable: the link just doesn't open anything.
                Err _ ->
                    ( model, Cmd.none )

        -- A post card's audio moving to the bar: its server must be one we're connected to (a federated attachment
        -- isn't ours to open), and the card only knows the track's id, so it's fetched first.
        AudioHandoffRequested (Just handoff) ->
            if RellmServers.knownConnectedRellmServer model.accounts.servers handoff.host /= Nothing then
                ( model, fetchTrack model handoff.host handoff.id (GotHandoffTrack handoff model.panels.audioPlayerPanel.selectionGeneration) )

            else
                ( model, Cmd.none )

        AudioHandoffRequested Nothing ->
            ( model, Cmd.none )

        GotHandoffTrack handoff generation result ->
            case result of
                Ok ( maybeAccountsPanelMsg, response ) ->
                    let
                        ( accountsPanelModel, accountsPanelCmd ) =
                            case maybeAccountsPanelMsg of
                                Just accountsPanelMsg ->
                                    AccountsPanel.update req accountsPanelMsg model.accounts

                                Nothing ->
                                    ( model.accounts, Cmd.none )

                        withAccounts : Model
                        withAccounts =
                            { model | accounts = accountsPanelModel }
                    in
                    case ( model.panels.audioPlayerPanel.selectionGeneration == generation, List.head response.media ) of
                        ( True, Just media ) ->
                            let
                                ( opened, openCmd ) =
                                    sharedUpdate req
                                        (AudioPlayerPanelMsg
                                            (AudioPlayerPanel.OpenAt
                                                [ MediaViewerPanel.mediaToReference media ]
                                                media.id
                                                handoff.host
                                                handoff.positionMs
                                                handoff.playing
                                            )
                                        )
                                        withAccounts
                            in
                            ( opened, Cmd.batch [ Cmd.map AccountsPanelMsg accountsPanelCmd, openCmd ] )

                        -- The player was closed or moved on while this was being fetched: it's no longer wanted.
                        _ ->
                            ( withAccounts, Cmd.map AccountsPanelMsg accountsPanelCmd )

                -- Missing, private or unreachable: the card's audio just stays where it is.
                Err _ ->
                    ( model, Cmd.none )

        AudioPlayerPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd ) =
                    AudioPlayerPanel.update subMsg panels.audioPlayerPanel

                -- The player's Edit button hands the current track to the viewer's editor.
                ( viewerModel, viewerCmd ) =
                    case ( subMsg == AudioPlayerPanel.EditClicked, AudioPlayerPanel.currentMedia subModel ) of
                        ( True, Just media ) ->
                            let
                                ( opened, openCmd, _ ) =
                                    MediaViewerPanel.update model.accounts
                                        (MediaViewerPanel.Open [ media ] Nothing media.id subModel.targetHost)
                                        panels.mediaViewerPanel

                                -- The player is already playing this track.
                                ( quiet, _, _ ) =
                                    MediaViewerPanel.update model.accounts MediaViewerPanel.OpenedForEditing opened

                                ( editing, editCmd, _ ) =
                                    MediaViewerPanel.update model.accounts MediaViewerPanel.EditClicked quiet
                            in
                            ( editing, Cmd.map MediaViewerPanelMsg (Cmd.batch [ openCmd, editCmd ]) )

                        _ ->
                            ( panels.mediaViewerPanel, Cmd.none )
            in
            ( { model
                | panels =
                    { panels
                        | audioPlayerPanel = subModel
                        , mediaViewerPanel = viewerModel
                        , videoPlayerPanel = syncVideoPanel panels.audioPlayerPanel subModel panels.videoPlayerPanel
                    }
              }
            , Cmd.batch [ Cmd.map AudioPlayerPanelMsg subCmd, viewerCmd ]
            )

        -- The miniplayer is the view of the queue's current video entry (`AudioPlayerPanel`'s queue is the app's one queue,
        -- for audio and video): what happens in it goes to the queue, and the queue decides what it shows (`syncVideoPanel`).
        VideoPlayerPanelMsg subMsg ->
            let
                toQueue : AudioPlayerPanel.Msg -> ( Model, Cmd Msg )
                toQueue queueMsg =
                    sharedUpdate req (AudioPlayerPanelMsg queueMsg) model
            in
            case subMsg of
                VideoPlayerPanel.Requested video ->
                    toQueue
                        (AudioPlayerPanel.OpenVideo
                            { src = video.src, poster = video.poster, aspectRatio = video.aspectRatio, returnUrl = video.returnUrl, mediaId = video.mediaId, host = video.host, downloads = video.downloads, postUrl = video.postUrl }
                            video.title
                            video.startAt
                            video.resume
                        )

                VideoPlayerPanel.Reported report ->
                    toQueue
                        (if report.ended then
                            AudioPlayerPanel.VideoEnded

                         else
                            AudioPlayerPanel.VideoState report.playing report.positionMs report.durationMs
                        )

                VideoPlayerPanel.CloseClicked ->
                    toQueue AudioPlayerPanel.Close

                VideoPlayerPanel.QueueClicked ->
                    toQueue AudioPlayerPanel.ShowQueue

                -- "Open in the viewer": the viewer shows the video as a stand-in media (just its URL) and takes over from where it is
                -- (`viewerVideoSync` plays it in this very player, which glides over the viewer's stage).
                VideoPlayerPanel.EnlargeClicked ->
                    case model.panels.videoPlayerPanel.video of
                        Just video ->
                            let
                                standIn : MediaReference
                                standIn =
                                    MediaViewerPanel.standInMedia { id = Maybe.withDefault video.src video.mediaId, url = video.src, title = video.title }

                                ( opened, openCmd, _ ) =
                                    MediaViewerPanel.update model.accounts
                                        (MediaViewerPanel.Open [ standIn ] Nothing standIn.id MediaViewerPanel.standInHost)
                                        model.panels.mediaViewerPanel
                            in
                            ( { model | panels = (\panels -> { panels | mediaViewerPanel = opened }) model.panels }, Cmd.map MediaViewerPanelMsg openCmd )

                        Nothing ->
                            ( model, Cmd.none )

                -- "Shrink to the miniplayer": closing the viewer takes its stage away, and the player glides to the corner, still playing.
                -- (The expanded player springs back when the viewer closes, so it is collapsed too, or the video would just land there.)
                VideoPlayerPanel.ShrinkClicked ->
                    let
                        ( closed, closeCmd, _ ) =
                            MediaViewerPanel.update model.accounts MediaViewerPanel.CloseClicked model.panels.mediaViewerPanel

                        withViewerClosed : Model
                        withViewerClosed =
                            { model | panels = (\panels -> { panels | mediaViewerPanel = closed }) model.panels }

                        ( collapsed, collapseCmd ) =
                            if withViewerClosed.panels.audioPlayerPanel.expanded then
                                sharedUpdate req (AudioPlayerPanelMsg AudioPlayerPanel.ToggleExpanded) withViewerClosed

                            else
                                ( withViewerClosed, Cmd.none )
                    in
                    ( collapsed, Cmd.batch [ Cmd.map MediaViewerPanelMsg closeCmd, collapseCmd ] )

                VideoPlayerPanel.Show _ ->
                    ( setVideoPanel (VideoPlayerPanel.update subMsg) model, Cmd.none )

                VideoPlayerPanel.Hide ->
                    ( setVideoPanel (VideoPlayerPanel.update subMsg) model, Cmd.none )

                VideoPlayerPanel.NoOp ->
                    ( model, Cmd.none )

        MediaRendererMsg subMsg ->
            ( { model | mediaRenderer = MediaRenderer.update subMsg model.mediaRenderer }, Cmd.none )

        BreadcrumbsMsg subMsg ->
            let
                breadcrumbsModel : Model
                breadcrumbsModel =
                    { model | breadcrumbs = Breadcrumbs.update subMsg model.breadcrumbs }
            in
            case subMsg of
                Breadcrumbs.SetRoot _ _ _ ->
                    sharedUpdate req CloseAllPanels breadcrumbsModel

                -- Its popover and the Countabilibar's share the same spot under the nav, so only one
                -- of them is ever open.
                Breadcrumbs.SegmentClicked _ ->
                    closeCountabilibarPanel breadcrumbsModel

                Breadcrumbs.ViewHost ->
                    closeCountabilibarPanel breadcrumbsModel

                _ ->
                    ( breadcrumbsModel, Cmd.none )

        CountabilibarSync subMsg ->
            sharedUpdate req (CountabilibarMsg subMsg) model

        CountabilibarMsg subMsg ->
            let
                ( countabilibarModel, countabilibarCmd ) =
                    Countabilibar.update subMsg model.countabilibar

                opensPanel : Bool
                opensPanel =
                    case subMsg of
                        Countabilibar.TogglePanel _ ->
                            Countabilibar.isPanelOpen countabilibarModel

                        _ ->
                            False

                updated : Model
                updated =
                    { model
                        | countabilibar = countabilibarModel
                        , breadcrumbs =
                            if opensPanel then
                                Breadcrumbs.update Breadcrumbs.CloseViewer model.breadcrumbs

                            else
                                model.breadcrumbs
                    }
            in
            ( updated, Cmd.map CountabilibarMsg countabilibarCmd )

        MarkdownPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                -- `Shared.CreateNewPanel`'s own draft content, if this exact
                -- `SaveClicked` is the one closing out its
                -- `MarkdownPanel.NewPostContent` edit -- read off
                -- `panels.markdownPanel.content` *before* `MarkdownPanel.update`
                -- (below) resets it back to `init`, since `MarkdownPanel`
                -- itself has no Post to save this to (see `TargetType`'s own
                -- doc on `NewPostContent`) and so never hands it back on its
                -- own `Msg`.
                savedNewPostContent : Maybe String
                savedNewPostContent =
                    case ( subMsg, panels.markdownPanel.target ) of
                        ( MarkdownPanel.SaveClicked, Just (MarkdownPanel.NewPostContent _) ) ->
                            Just panels.markdownPanel.content

                        _ ->
                            Nothing

                -- `True` only right as a `SendNewMessage` save actually
                -- succeeds -- read off `panels.markdownPanel.target` *before*
                -- `MarkdownPanel.update` (below) resets it back to `init`,
                -- same "read the pre-update state" trick `savedNewPostContent`
                -- above uses. Drives refetching `Shared.MessagingPanel`'s own
                -- embedded listing (see `refreshedMessagingPanel` below) so a
                -- just-sent message shows up there without waiting for its
                -- next 30s poll -- the routed `/messages` page gets the same
                -- treatment via `Pages.Messages`'s own `SharedMsg` handling of
                -- this exact forwarded message (see `Main.notifyPageOfSharedMsg`).
                messageJustSent : Bool
                messageJustSent =
                    case subMsg of
                        MarkdownPanel.GotSendMessageResult (Ok _) ->
                            True

                        _ ->
                            False

                ( subModel, subCmd, ( maybeAccountsPanelMsg, showScrollPreserver, cancelRequested ) ) =
                    MarkdownPanel.update model.accounts subMsg panels.markdownPanel

                ( refreshedMessagingPanel, refreshMessagingPanelCmd ) =
                    if messageJustSent then
                        let
                            -- `ForceRefresh`, not `Poll` -- see that
                            -- constructor's own doc: `Poll`'s own
                            -- `fetchNewServers` only fetches newly-eligible
                            -- servers, so it would silently no-op here once
                            -- this panel's already been opened once this
                            -- session (the common case) and had time to
                            -- fetch its own listing already.
                            ( m, cmd, _ ) =
                                MessagingPanel.update model.accounts (MessagingPanel.PageMsg MessagesPage.ForceRefresh) panels.messagingPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.messagingPanel, Cmd.none )

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                scrollPreserverCmd : Cmd Msg
                scrollPreserverCmd =
                    if showScrollPreserver then
                        Task.perform (\() -> ShowScrollPreserver) (Task.succeed ())

                    else
                        Cmd.none

                -- `MarkdownPanel.CancelClicked`'s own request (see its doc)
                -- to open the shared "are you sure?" dialog -- same
                -- `RequestDelete` `MyMediaPanel.DeleteClicked` triggers,
                -- just with no payload (see `ConfirmMarkdownEditingDataLost`'s
                -- own doc).
                confirmingDeleteFor : Maybe DeleteConfirmation
                confirmingDeleteFor =
                    if cancelRequested then
                        Just ConfirmMarkdownEditingDataLost

                    else
                        panels.confirmingDeleteFor

                ( createNewPanelModel, createNewPanelCmd ) =
                    case savedNewPostContent of
                        Just content ->
                            let
                                ( m, cmd, _ ) =
                                    CreateNewPanel.update model.time.browserTimeZone model.time.now model.accounts (CreateNewPanel.ContentSaved content) panels.createNewPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.createNewPanel, Cmd.none )
            in
            ( { model
                | accounts = accountsPanelModel
                , panels =
                    { panels
                        | markdownPanel = subModel
                        , createNewPanel = createNewPanelModel
                        , confirmingDeleteFor = confirmingDeleteFor
                        , messagingPanel = refreshedMessagingPanel
                    }
              }
            , Cmd.batch
                [ Cmd.map MarkdownPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , scrollPreserverCmd
                , Cmd.map CreateNewPanelMsg createNewPanelCmd
                , Cmd.map MessagingPanelMsg refreshMessagingPanelCmd
                ]
            )

        MediaGeneratorPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd, ( maybeAccountsPanelMsg, maybeMyMediaPanelMsg ) ) =
                    MediaGeneratorPanel.update model.accounts subMsg panels.mediaGeneratorPanel

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- `MediaGeneratorPanel.EditMediaClicked`'s own request (see its module doc) to
                -- actually open `MyMediaPanel` on its behalf -- it can't dispatch that directly
                -- without importing `Shared`, which would cycle. Mirrors `CreateNewPanelMsg`'s own
                -- `maybeMyMediaPanelMsg` handling above exactly.
                ( myMediaPanelModel, myMediaPanelCmd ) =
                    case maybeMyMediaPanelMsg of
                        Just myMediaPanelMsg ->
                            let
                                ( m, cmd, _ ) =
                                    MyMediaPanel.update accountsPanelModel myMediaPanelMsg panels.myMediaPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.myMediaPanel, Cmd.none )
            in
            ( { model
                | accounts = accountsPanelModel
                , panels = { panels | mediaGeneratorPanel = subModel, myMediaPanel = myMediaPanelModel }
              }
            , Cmd.batch
                [ Cmd.map MediaGeneratorPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , Cmd.map MyMediaPanelMsg myMediaPanelCmd
                ]
            )

        MyMediaPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                -- `Shared.CreateNewPanel`'s own picked media, if this exact
                -- `SaveMediaClicked` is the one closing out the `MultiSelect`
                -- it opened (`EditMediaClicked`) -- gated on it currently
                -- being open, same "am I mid-edit" reasoning
                -- `Pages.Post.PostId_.mediaEditActive` uses for its own,
                -- page-level `MultiSelect` consumer (see `MyMediaPanel`'s own
                -- module doc).
                savedMedia : Maybe (List Proto.Rellm.MediaReference)
                savedMedia =
                    case subMsg of
                        MyMediaPanel.SaveMediaClicked media ->
                            if CreateNewPanel.isOpen panels.createNewPanel then
                                Just media

                            else
                                Nothing

                        _ ->
                            Nothing

                -- `Shared.MediaGeneratorPanel`'s own `EditMediaClicked` request, picked up the same
                -- way `savedMedia`/`createNewPanelModel` above do for `CreateNewPanel` -- gated on
                -- `mediaEditActive`, not just `isOpen`, since this panel staying open doesn't by
                -- itself mean *it* was who opened `MyMediaPanel` just now (see that field's own
                -- doc). `CloseClicked` (a cancel) is forwarded too, so `mediaEditActive` doesn't
                -- linger `True` after backing out of the picker without saving.
                mediaGeneratorMsg : Maybe MediaGeneratorPanel.Msg
                mediaGeneratorMsg =
                    if panels.mediaGeneratorPanel.mediaEditActive then
                        case subMsg of
                            MyMediaPanel.SaveMediaClicked media ->
                                Just (MediaGeneratorPanel.MediaSaved media)

                            MyMediaPanel.CloseClicked ->
                                Just MediaGeneratorPanel.MediaEditClosed

                            _ ->
                                Nothing

                    else
                        Nothing

                ( subModel, subCmd, ( maybeAccountsPanelMsg, maybeDeleteRequest, maybeMediaViewerPanelMsg ) ) =
                    MyMediaPanel.update model.accounts subMsg panels.myMediaPanel

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- `MyMediaPanel.DeleteClicked`'s own request (see its doc) to
                -- open the shared "are you sure?" dialog -- same
                -- `RequestDelete` a plain `Shared.Msg` click (`serverChip`/
                -- `accountRow`) would fire directly, just routed through this
                -- panel's own `Msg` space instead since its `view` is fully
                -- `Html.map`-wrapped (see `UI.myMediaPanel`).
                confirmingDeleteFor : Maybe DeleteConfirmation
                confirmingDeleteFor =
                    case maybeDeleteRequest of
                        Just media ->
                            Just (ConfirmMediaDelete media)

                        Nothing ->
                            panels.confirmingDeleteFor

                ( createNewPanelModel, createNewPanelCmd ) =
                    case savedMedia of
                        Just media ->
                            let
                                ( m, cmd, _ ) =
                                    CreateNewPanel.update model.time.browserTimeZone model.time.now model.accounts (CreateNewPanel.MediaSaved media) panels.createNewPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.createNewPanel, Cmd.none )

                ( mediaGeneratorPanelModel, mediaGeneratorPanelCmd ) =
                    case mediaGeneratorMsg of
                        Just innerMsg ->
                            let
                                ( m, cmd, _ ) =
                                    MediaGeneratorPanel.update model.accounts innerMsg panels.mediaGeneratorPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.mediaGeneratorPanel, Cmd.none )

                -- `MediaItemClicked` in Browse mode (see `MyMediaPanel.update`'s
                -- own doc) -- opens `Shared.MediaViewerPanel` on the tapped
                -- tile, same forwarding convention `StarredPanelMsg`'s own
                -- `maybeMediaViewerPanelMsg` uses above.
                ( mediaViewerPanelModel, mediaViewerPanelCmd, maybeMediaViewerAccountsPanelMsg ) =
                    case maybeMediaViewerPanelMsg of
                        Just mediaViewerPanelMsg ->
                            MediaViewerPanel.update model.accounts mediaViewerPanelMsg panels.mediaViewerPanel

                        Nothing ->
                            ( panels.mediaViewerPanel, Cmd.none, Nothing )

                -- `MediaViewerPanel.update`'s own account-refresh, if any -- see `StarredPanelMsg`'s
                -- own `finalAccountsPanelModel` for why this is layered on top rather than replacing.
                ( finalAccountsPanelModel, mediaViewerAccountsCmd ) =
                    case maybeMediaViewerAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg accountsPanelModel

                        Nothing ->
                            ( accountsPanelModel, Cmd.none )
            in
            ( { model
                | accounts = finalAccountsPanelModel
                , panels =
                    { panels
                        | myMediaPanel = subModel
                        , confirmingDeleteFor = confirmingDeleteFor
                        , createNewPanel = createNewPanelModel
                        , mediaGeneratorPanel = mediaGeneratorPanelModel
                        , mediaViewerPanel = mediaViewerPanelModel
                    }
              }
            , Cmd.batch
                [ Cmd.map MyMediaPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , Cmd.map AccountsPanelMsg mediaViewerAccountsCmd
                , Cmd.map CreateNewPanelMsg createNewPanelCmd
                , Cmd.map MediaGeneratorPanelMsg mediaGeneratorPanelCmd
                , Cmd.map MediaViewerPanelMsg mediaViewerPanelCmd
                ]
            )

        PostsCacheMsg subMsg ->
            ( { model | postsCache = PostsCache.update subMsg model.postsCache }, Cmd.none )

        EventsCacheMsg subMsg ->
            ( { model | eventsCache = EventsCache.update subMsg model.eventsCache }, Cmd.none )

        QuoteLinksMsg subMsg ->
            let
                ( quoteLinks, quoteCmd, accountsPanelMsgs ) =
                    QuoteLinks.update model.accounts subMsg model.quoteLinks
            in
            -- What a fetch needs sent to `AccountsPanel` on its behalf (a preview connection to load, a
            -- refreshed token to save) goes through the same update every other `AccountsPanelMsg` does.
            List.foldl
                (\accountsPanelMsg ( accumulatedModel, cmds ) ->
                    let
                        ( nextModel, nextCmd ) =
                            sharedUpdate req (AccountsPanelMsg accountsPanelMsg) accumulatedModel
                    in
                    ( nextModel, nextCmd :: cmds )
                )
                ( { model | quoteLinks = quoteLinks }, [ Cmd.map QuoteLinksMsg quoteCmd ] )
                accountsPanelMsgs
                |> Tuple.mapSecond Cmd.batch

        CreateNewPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                -- The quote button on a post's page hands over the post it's already holding -- seeded
                -- into the quote cache so the preview doesn't refetch it.
                quoteLinksAfter : QuoteLinks.Model
                quoteLinksAfter =
                    case subMsg of
                        CreateNewPanel.OpenQuoting host post ->
                            let
                                ( seeded, _, _ ) =
                                    QuoteLinks.update model.accounts (QuoteLinks.Provide host post) model.quoteLinks
                            in
                            seeded

                        _ ->
                            model.quoteLinks

                ( subModel, subCmd, ( maybeAccountsPanelMsg, maybeMarkdownPanelMsg, maybeMyMediaPanelMsg ) ) =
                    CreateNewPanel.update model.time.browserTimeZone model.time.now model.accounts subMsg panels.createNewPanel

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- `CreateNewPanel.EditContentClicked`/`EditMediaClicked`'s own
                -- request (see its module doc) to actually open
                -- `MarkdownPanel`/`MyMediaPanel` on its behalf -- it can't
                -- dispatch either directly without importing `Shared`, which
                -- would cycle.
                ( markdownPanelModel, markdownPanelCmd ) =
                    case maybeMarkdownPanelMsg of
                        Just markdownPanelMsg ->
                            let
                                ( m, cmd, _ ) =
                                    MarkdownPanel.update accountsPanelModel markdownPanelMsg panels.markdownPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.markdownPanel, Cmd.none )

                ( myMediaPanelModel, myMediaPanelCmd ) =
                    case maybeMyMediaPanelMsg of
                        Just myMediaPanelMsg ->
                            let
                                ( m, cmd, _ ) =
                                    MyMediaPanel.update accountsPanelModel myMediaPanelMsg panels.myMediaPanel
                            in
                            ( m, cmd )

                        Nothing ->
                            ( panels.myMediaPanel, Cmd.none )

                -- Mirrors `StarredPanelMsg`'s own
                -- `shouldCloseCreateNewPanel`, in the other direction --
                -- unconditional (not narrow-screen-gated), same reasoning.
                shouldCloseStarredPanel : Bool
                shouldCloseStarredPanel =
                    case subMsg of
                        CreateNewPanel.ToggleOpen ->
                            subModel.open

                        CreateNewPanel.OpenQuoting _ _ ->
                            True

                        _ ->
                            False

                ( closedStarredPanelModel, closeStarredPostsCmd ) =
                    if shouldCloseStarredPanel then
                        let
                            ( m, cmd, _ ) =
                                StarredPanel.update accountsPanelModel StarredPanel.CloseStarredPanel panels.starredPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.starredPanel, Cmd.none )

                -- Mirrors `AccountsPanelMsg`'s own `shouldCloseCreateNewPanel`,
                -- in the other direction -- see its own doc.
                shouldCloseAccountsPanel : Bool
                shouldCloseAccountsPanel =
                    case subMsg of
                        CreateNewPanel.ToggleOpen ->
                            subModel.open

                        CreateNewPanel.OpenQuoting _ _ ->
                            True

                        _ ->
                            False

                ( closedAccountsPanelModel, closeAccountsCmd ) =
                    if shouldCloseAccountsPanel then
                        AccountsPanel.update req AccountsPanel.CloseAccountsPanel accountsPanelModel

                    else
                        ( accountsPanelModel, Cmd.none )

                -- Mirrors `shouldCloseStarredPanel` above -- the New
                -- Post/Event panel opens at the same vertical position as
                -- the Messaging panel too.
                shouldCloseMessagingPanel : Bool
                shouldCloseMessagingPanel =
                    case subMsg of
                        CreateNewPanel.ToggleOpen ->
                            subModel.open

                        CreateNewPanel.OpenQuoting _ _ ->
                            True

                        _ ->
                            False

                ( closedMessagingPanelModel, closeMessagingCmd ) =
                    if shouldCloseMessagingPanel then
                        let
                            ( m, cmd, _ ) =
                                MessagingPanel.update accountsPanelModel MessagingPanel.CloseMessagingPanel panels.messagingPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.messagingPanel, Cmd.none )
            in
            ( { model
                | accounts = closedAccountsPanelModel
                , quoteLinks = quoteLinksAfter
                , panels =
                    { panels
                        | createNewPanel = subModel
                        , markdownPanel = markdownPanelModel
                        , myMediaPanel = myMediaPanelModel
                        , starredPanel = closedStarredPanelModel
                        , messagingPanel = closedMessagingPanelModel
                    }
              }
            , Cmd.batch
                [ Cmd.map CreateNewPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , Cmd.map AccountsPanelMsg closeAccountsCmd
                , Cmd.map MarkdownPanelMsg markdownPanelCmd
                , Cmd.map MyMediaPanelMsg myMediaPanelCmd
                , Cmd.map StarredPanelMsg closeStarredPostsCmd
                , Cmd.map MessagingPanelMsg closeMessagingCmd
                ]
            )

        MyMediaPanelOpenForAccount account ->
            -- The media button on an Account chip (`UI.accountRow`) opens this
            -- panel for that account's server -- mirrors `HomeLinkClicked`'s own
            -- multi-panel composition via `sharedUpdate`. The chip is clickable for
            -- disabled (signed-out-of-aggregation) accounts too, so bring the
            -- account along into `enabled` here, the same as clicking its switch
            -- (`AccountsPanel.ToggleAccountEnabled`), rather than silently
            -- browsing an account the Accounts Panel still shows as off.
            let
                host : String
                host =
                    account.server

                ( enabledModel, enableCmd ) =
                    if account.enabled then
                        ( model, Cmd.none )

                    else
                        sharedUpdate req (AccountsPanelMsg (AccountsPanel.ToggleAccountEnabled (RellmAccounts.rellmAccountId account))) model

                ( openedModel, openCmd ) =
                    sharedUpdate req (MyMediaPanelMsg (MyMediaPanel.Open Nothing host)) enabledModel

                -- The avatar menu (`UI.accountAvatarMenuView`) this "Media" click came from is now
                -- superseded by the panel it just opened -- collapse it too, rather than leaving the
                -- row sitting expanded behind `MyMediaPanel`.
                ( closedPopoverModel, closePopoverCmd ) =
                    sharedUpdate req (AccountsPanelMsg AccountsPanel.CloseFocusedAccount) openedModel
            in
            ( closedPopoverModel, Cmd.batch [ enableCmd, openCmd, closePopoverCmd ] )

        -- An `AccountsPanel`/`UI.accountAvatarMenuView` "Subscriptions"/"Sync
        -- Sources"/"Sync Destinations"/"AI Models" item -- unlike a plain
        -- `href` link, this always fires (see that view's own doc on why a
        -- bare link can't do the job): a `Nav.pushUrl` for the general case
        -- (a fresh `#`-seeded `init`, same as any other profile deep link --
        -- see `Components.Pages.UserProfilePage.init`'s own `fragment`
        -- handling), plus this same `Shared.Msg` gets forwarded straight into
        -- whichever page is *currently* mounted too (`Main.notifyPageOfSharedMsg`,
        -- automatic for every `Shared.Msg`) -- if that's already this exact
        -- profile, `UserProfilePage.update`'s own `SharedMsg` branch expands
        -- and scrolls to `sectionId` immediately, since `pushUrl` to an
        -- unchanged path is a silent no-op there (`Main.ChangedUrl`'s own
        -- `url.path == model.url.path` branch never re-`init`s or notifies
        -- the page at all).
        ProfileSectionLinkClicked account sectionId ->
            let
                profileHref : String
                profileHref =
                    Users.profileHref model.basePath model.accounts.mainFrontendHost account.server { userId = account.userId, username = account.username }

                ( closedModel, closeCmd ) =
                    sharedUpdate req (AccountsPanelMsg AccountsPanel.CloseAccountsPanel) model
            in
            ( closedModel
            , Cmd.batch [ closeCmd, Nav.pushUrl req.key (profileHref ++ "#" ++ sectionId) ]
            )

        ContactMethodPhoneSaveClicked ->
            case ( AccountsPanel.freshFocusedAccount model.accounts, (AccountsPanel.currentFocusedAccountContactMethods model.accounts).phoneEdit ) of
                ( Just account, Just edit ) ->
                    let
                        accounts : AccountsPanel.Model
                        accounts =
                            model.accounts

                        current : RellmAccounts.RellmContactMethods
                        current =
                            AccountsPanel.currentFocusedAccountContactMethods model.accounts
                    in
                    ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | phoneEdit = Just { edit | status = RellmAccounts.Submitting } } } }
                    , Users.updateUser model.accounts
                        ( Just account.userId, account.server )
                        account.userId
                        (\freshUser ->
                            { freshUser
                                | phone =
                                    Just
                                        { value = Just ("tel:" ++ edit.input)
                                        , visibility = edit.visibility
                                        , supportedByServer = False
                                        , verifiedAt = Nothing
                                        , verificationInProgress = Nothing

                                        -- Consent is edited separately (`ContactMethodPhoneConsentToggled`) --
                                        -- always carried forward from the just-refetched `freshUser.phone`,
                                        -- same reasoning as `Components.Pages.UserProfilePage.PhoneSaveClicked`.
                                        , consentState = freshUser.phone |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED
                                        , consentHistory = freshUser.phone |> Maybe.map .consentHistory |> Maybe.withDefault []
                                        }
                            }
                        )
                        |> Task.attempt GotContactMethodPhoneSaveTaskResult
                    )

                _ ->
                    ( model, Cmd.none )

        GotContactMethodPhoneSaveTaskResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodPhoneSaveResult (Ok updatedUser))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodPhoneSaveTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodPhoneSaveResult (Err err))) model

        ContactMethodEmailSaveClicked ->
            case ( AccountsPanel.freshFocusedAccount model.accounts, (AccountsPanel.currentFocusedAccountContactMethods model.accounts).emailEdit ) of
                ( Just account, Just edit ) ->
                    let
                        accounts : AccountsPanel.Model
                        accounts =
                            model.accounts

                        current : RellmAccounts.RellmContactMethods
                        current =
                            AccountsPanel.currentFocusedAccountContactMethods model.accounts
                    in
                    ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | emailEdit = Just { edit | status = RellmAccounts.Submitting } } } }
                    , Users.updateUser model.accounts
                        ( Just account.userId, account.server )
                        account.userId
                        (\freshUser ->
                            { freshUser
                                | email =
                                    Just
                                        { value = Just ("mailto:" ++ edit.input)
                                        , visibility = edit.visibility
                                        , supportedByServer = False
                                        , verifiedAt = Nothing
                                        , verificationInProgress = Nothing

                                        -- Same reasoning as `ContactMethodPhoneSaveClicked` above --
                                        -- consent is edited separately, so it's always carried forward
                                        -- unchanged here.
                                        , consentState = freshUser.email |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED
                                        , consentHistory = freshUser.email |> Maybe.map .consentHistory |> Maybe.withDefault []
                                        }
                            }
                        )
                        |> Task.attempt GotContactMethodEmailSaveTaskResult
                    )

                _ ->
                    ( model, Cmd.none )

        GotContactMethodEmailSaveTaskResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodEmailSaveResult (Ok updatedUser))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodEmailSaveTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodEmailSaveResult (Err err))) model

        ContactMethodPhoneConsentToggled ->
            case AccountsPanel.freshFocusedAccount model.accounts of
                Just account ->
                    let
                        newConsent : ContactConsentState
                        newConsent =
                            if (account.phone |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED) == CONTACTCONSENTGRANTED then
                                CONTACTCONSENTREVOKED

                            else
                                CONTACTCONSENTGRANTED

                        accounts : AccountsPanel.Model
                        accounts =
                            model.accounts

                        current : RellmAccounts.RellmContactMethods
                        current =
                            AccountsPanel.currentFocusedAccountContactMethods model.accounts
                    in
                    ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | phoneConsentStatus = RellmAccounts.Submitting } } }
                    , Users.updateUser model.accounts
                        ( Just account.userId, account.server )
                        account.userId
                        (\freshUser -> { freshUser | phone = freshUser.phone |> Maybe.map (\cm -> { cm | consentState = newConsent }) })
                        |> Task.attempt GotContactMethodPhoneConsentTaskResult
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotContactMethodPhoneConsentTaskResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodPhoneConsentResult (Ok updatedUser))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodPhoneConsentTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodPhoneConsentResult (Err err))) model

        ContactMethodEmailConsentToggled ->
            case AccountsPanel.freshFocusedAccount model.accounts of
                Just account ->
                    let
                        newConsent : ContactConsentState
                        newConsent =
                            if (account.email |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED) == CONTACTCONSENTGRANTED then
                                CONTACTCONSENTREVOKED

                            else
                                CONTACTCONSENTGRANTED

                        accounts : AccountsPanel.Model
                        accounts =
                            model.accounts

                        current : RellmAccounts.RellmContactMethods
                        current =
                            AccountsPanel.currentFocusedAccountContactMethods model.accounts
                    in
                    ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | emailConsentStatus = RellmAccounts.Submitting } } }
                    , Users.updateUser model.accounts
                        ( Just account.userId, account.server )
                        account.userId
                        (\freshUser -> { freshUser | email = freshUser.email |> Maybe.map (\cm -> { cm | consentState = newConsent }) })
                        |> Task.attempt GotContactMethodEmailConsentTaskResult
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotContactMethodEmailConsentTaskResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodEmailConsentResult (Ok updatedUser))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodEmailConsentTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodEmailConsentResult (Err err))) model

        ContactMethodStartPhoneVerificationClicked ->
            case AccountsPanel.freshFocusedAccount model.accounts of
                Just account ->
                    case account.phone of
                        Just contactMethod ->
                            let
                                accounts : AccountsPanel.Model
                                accounts =
                                    model.accounts

                                current : RellmAccounts.RellmContactMethods
                                current =
                                    AccountsPanel.currentFocusedAccountContactMethods model.accounts

                                pendingVerification : RellmAccounts.PhoneVerification
                                pendingVerification =
                                    current.phoneVerification
                                        |> Maybe.map (\pv -> { pv | sendStatus = RellmAccounts.Submitting })
                                        |> Maybe.withDefault { sendStatus = RellmAccounts.Submitting, code = "", verifyStatus = RellmAccounts.Idle, cooldownActive = False }
                            in
                            ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | phoneVerification = Just pendingVerification } } }
                            , Users.startContactMethodVerification model.accounts ( Just account.userId, account.server ) contactMethod
                                |> Task.attempt GotContactMethodStartPhoneVerificationTaskResult
                            )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        GotContactMethodStartPhoneVerificationTaskResult (Ok ( maybeAccountsPanelMsg, updatedContactMethod )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodStartPhoneVerificationResult (Ok updatedContactMethod))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodStartPhoneVerificationTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodStartPhoneVerificationResult (Err err))) model

        ContactMethodVerifyPhoneCodeClicked ->
            case ( AccountsPanel.freshFocusedAccount model.accounts, (AccountsPanel.currentFocusedAccountContactMethods model.accounts).phoneVerification ) of
                ( Just account, Just pendingVerification ) ->
                    case account.phone |> Maybe.andThen .value of
                        Just phoneValue ->
                            let
                                accounts : AccountsPanel.Model
                                accounts =
                                    model.accounts

                                current : RellmAccounts.RellmContactMethods
                                current =
                                    AccountsPanel.currentFocusedAccountContactMethods model.accounts
                            in
                            ( { model | accounts = { accounts | focusedAccountContactMethods = Just { current | phoneVerification = Just { pendingVerification | verifyStatus = RellmAccounts.Submitting } } } }
                            , Users.verifyContactMethod model.accounts
                                ( Just account.userId, account.server )
                                { value = phoneValue, code = pendingVerification.code }
                                |> Task.attempt GotContactMethodVerifyPhoneCodeTaskResult
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotContactMethodVerifyPhoneCodeTaskResult (Ok ( maybeAccountsPanelMsg, updatedContactMethod )) ->
            let
                ( afterToken, tokenCmd ) =
                    maybeAccountsPanelMsg
                        |> Maybe.map (\m -> sharedUpdate req (AccountsPanelMsg m) model)
                        |> Maybe.withDefault ( model, Cmd.none )

                ( finalModel, applyCmd ) =
                    sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodVerifyPhoneCodeResult (Ok updatedContactMethod))) afterToken
            in
            ( finalModel, Cmd.batch [ tokenCmd, applyCmd ] )

        GotContactMethodVerifyPhoneCodeTaskResult (Err err) ->
            sharedUpdate req (AccountsPanelMsg (AccountsPanel.GotContactMethodVerifyPhoneCodeResult (Err err))) model

        MessagingPanelMsg subMsg ->
            let
                panels : Panels
                panels =
                    model.panels

                ( subModel, subCmd, maybeAccountsPanelMsg ) =
                    MessagingPanel.update model.accounts subMsg panels.messagingPanel

                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- Mirrors `StarredPanelMsg`'s own `shouldCloseAccountsPanel`.
                shouldCloseAccountsPanel : Bool
                shouldCloseAccountsPanel =
                    case subMsg of
                        MessagingPanel.ToggleOpen ->
                            subModel.open && Responsive.isNarrow model.windowSize

                        _ ->
                            False

                ( closedAccountsPanelModel, closeAccountsCmd ) =
                    if shouldCloseAccountsPanel then
                        AccountsPanel.update req AccountsPanel.CloseAccountsPanel accountsPanelModel

                    else
                        ( accountsPanelModel, Cmd.none )

                -- Mirrors `StarredPanelMsg`'s own `shouldCloseCreateNewPanel`
                -- (unconditional -- same overlapping vertical position).
                shouldCloseCreateNewPanel : Bool
                shouldCloseCreateNewPanel =
                    case subMsg of
                        MessagingPanel.ToggleOpen ->
                            subModel.open

                        _ ->
                            False

                ( closedCreateNewPanelModel, closeCreateNewCmd ) =
                    if shouldCloseCreateNewPanel then
                        let
                            ( m, cmd, _ ) =
                                CreateNewPanel.update model.time.browserTimeZone model.time.now closedAccountsPanelModel CreateNewPanel.CloseClicked panels.createNewPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.createNewPanel, Cmd.none )

                -- Mirrors `StarredPanelMsg`'s own reverse-direction
                -- `shouldCloseMessagingPanel` -- both are same-position
                -- `.navbar` dropdowns, so opening one closes the other
                -- outright.
                shouldCloseStarredPanel : Bool
                shouldCloseStarredPanel =
                    case subMsg of
                        MessagingPanel.ToggleOpen ->
                            subModel.open

                        _ ->
                            False

                ( closedStarredPanelModel, closeStarredCmd ) =
                    if shouldCloseStarredPanel then
                        let
                            ( m, cmd, _ ) =
                                StarredPanel.update closedAccountsPanelModel StarredPanel.CloseStarredPanel panels.starredPanel
                        in
                        ( m, cmd )

                    else
                        ( panels.starredPanel, Cmd.none )
            in
            ( { model
                | accounts = closedAccountsPanelModel
                , panels =
                    { panels
                        | messagingPanel = subModel
                        , createNewPanel = closedCreateNewPanelModel
                        , starredPanel = closedStarredPanelModel
                    }
              }
            , Cmd.batch
                [ Cmd.map MessagingPanelMsg subCmd
                , Cmd.map AccountsPanelMsg accountsPanelCmd
                , Cmd.map AccountsPanelMsg closeAccountsCmd
                , Cmd.map CreateNewPanelMsg closeCreateNewCmd
                , Cmd.map StarredPanelMsg closeStarredCmd
                ]
            )

        CloseAllPanels ->
            let
                ( closedAccountsModel, closeAccountsCmd ) =
                    sharedUpdate req (AccountsPanelMsg AccountsPanel.CloseAccountsPanel) model

                ( closedStarredModel, closeStarredCmd ) =
                    sharedUpdate req (StarredPanelMsg StarredPanel.CloseStarredPanel) closedAccountsModel

                ( closedCreateNewModel, closeCreateNewCmd ) =
                    sharedUpdate req (CreateNewPanelMsg CreateNewPanel.CloseClicked) closedStarredModel

                ( closedMessagingModel, closeMessagingCmd ) =
                    sharedUpdate req (MessagingPanelMsg MessagingPanel.CloseMessagingPanel) closedCreateNewModel
            in
            ( { closedMessagingModel | countabilibar = Countabilibar.closePanel closedMessagingModel.countabilibar }
            , Cmd.batch [ closeAccountsCmd, closeStarredCmd, closeCreateNewCmd, closeMessagingCmd ]
            )

        ThemePreferenceClicked ->
            let
                theme : Theme
                theme =
                    model.theme

                newPreference : ThemePreference
                newPreference =
                    nextThemePreference theme.preference
            in
            ( { model | theme = { theme | preference = newPreference } }
            , Cmd.batch
                [ Ports.setTheme (appliedTheme { model | theme = { theme | preference = newPreference } })
                , Ports.persistThemePreference (themePreferenceToString newPreference)
                ]
            )

        SystemPrefersDarkChanged prefersDark ->
            let
                theme : Theme
                theme =
                    model.theme
            in
            ( { model | theme = { theme | systemPrefersDark = prefersDark } }, Cmd.none )

        RequestDelete confirmation ->
            let
                panels : Panels
                panels =
                    model.panels
            in
            ( { model | panels = { panels | confirmingDeleteFor = Just confirmation } }, Cmd.none )

        CancelDelete ->
            let
                panels : Panels
                panels =
                    model.panels
            in
            ( { model | panels = { panels | confirmingDeleteFor = Nothing } }, Cmd.none )

        ConfirmDelete ->
            let
                panels : Panels
                panels =
                    model.panels
            in
            case panels.confirmingDeleteFor of
                -- These two route straight into `AccountsPanel.update`
                -- rather than resolving through `Task.attempt` + a
                -- `GotXDeleteResult` here, unlike every branch below. That's
                -- fine *only* because `AccountsPanel.Model` already lives on
                -- `Shared.Model` for unrelated reasons (it's real global
                -- state -- known servers, signed-in accounts -- read from
                -- all over the app); it's not a reason to give some other
                -- page-local delete a Shared-owned home just to reach this
                -- `case`. See `DeleteConfirmation`'s own doc.
                Just (ConfirmAccountDelete account) ->
                    let
                        ( subModel, subCmd ) =
                            AccountsPanel.update req (AccountsPanel.RemoveAccountClicked (RellmAccounts.rellmAccountId account)) model.accounts
                    in
                    ( { model | accounts = subModel, panels = { panels | confirmingDeleteFor = Nothing } }
                    , Cmd.map AccountsPanelMsg subCmd
                    )

                Just (ConfirmServerDelete server) ->
                    let
                        ( subModel, subCmd ) =
                            AccountsPanel.update req (AccountsPanel.RemoveServerClicked server.frontendHost) model.accounts
                    in
                    ( { model | accounts = subModel, panels = { panels | confirmingDeleteFor = Nothing } }
                    , Cmd.map AccountsPanelMsg subCmd
                    )

                -- Unlike the two branches above (which just flip local
                -- state), this actually calls `DeleteMedia` -- see
                -- `MyMediaPanel.deleteTask`. Its own `maybeAccountsPanelMsg`
                -- is forwarded the same way `MyMediaPanelMsg` above does;
                -- `DeleteConfirmed` never produces a delete request or a
                -- `MediaViewerPanel.Open` of its own (those are only
                -- `DeleteClicked`/`MediaItemClicked`), so its other two
                -- values are ignored here.
                Just (ConfirmMediaDelete media) ->
                    let
                        ( subModel, subCmd, ( maybeAccountsPanelMsg, _, _ ) ) =
                            MyMediaPanel.update model.accounts (MyMediaPanel.DeleteConfirmed media) panels.myMediaPanel

                        ( accountsPanelModel, accountsPanelCmd ) =
                            case maybeAccountsPanelMsg of
                                Just accountsPanelMsg ->
                                    AccountsPanel.update req accountsPanelMsg model.accounts

                                Nothing ->
                                    ( model.accounts, Cmd.none )
                    in
                    ( { model
                        | accounts = accountsPanelModel
                        , panels = { panels | myMediaPanel = subModel, confirmingDeleteFor = Nothing }
                      }
                    , Cmd.batch
                        [ Cmd.map MyMediaPanelMsg subCmd
                        , Cmd.map AccountsPanelMsg accountsPanelCmd
                        ]
                    )

                -- No RPC, no `AccountsPanel.Msg` to forward -- just discards
                -- `panels.markdownPanel.content` back to `init`, exactly what
                -- `CancelClicked` used to do directly before this
                -- confirmation step existed.
                Just ConfirmMarkdownEditingDataLost ->
                    let
                        ( subModel, subCmd, _ ) =
                            MarkdownPanel.update model.accounts MarkdownPanel.CancelConfirmed panels.markdownPanel
                    in
                    ( { model | panels = { panels | markdownPanel = subModel, confirmingDeleteFor = Nothing } }
                    , Cmd.map MarkdownPanelMsg subCmd
                    )

                -- Unlike every branch above, none of these three is owned by
                -- any Shared-owned panel to delegate a `DeleteConfirmed`
                -- into -- each fires its delete RPC directly instead,
                -- resolving the acting account from the carried `targetHost`.
                -- Each result (`GotSyncSourceDeleteResult`/
                -- `GotPostDeleteResult`/`GotEventDeleteResult`) is picked up
                -- by whichever page is active, same as any other
                -- `Shared.Msg` -- see `DeleteConfirmation`'s own doc for why
                -- this is the shape new page-owned deletable lists should
                -- follow.
                Just (ConfirmSyncSourceDelete source deleteSyncedEvents host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , SyncSources.deleteSyncSource
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        source
                        deleteSyncedEvents
                        |> Task.attempt GotSyncSourceDeleteResult
                    )

                Just (ConfirmDeleteLinkPreviewImages host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , MediaMaintenance.deleteLinkPreviewImages
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        |> Task.attempt GotLinkPreviewImagesDeleteResult
                    )

                Just (ConfirmPostDelete post host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Posts.deletePost
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        post.id
                        |> Task.attempt GotPostDeleteResult
                    )

                Just (ConfirmFederatedPostDelete post host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , case FederationActions.ownAccountFor model.accounts host post of
                        Just account ->
                            FederationActions.deletePost account post
                                |> Task.attempt GotFederatedPostDeleteResult

                        Nothing ->
                            Task.fail (Http.BadStatus 403)
                                |> Task.attempt GotFederatedPostDeleteResult
                    )

                Just (ConfirmEventDelete event host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Events.deleteEvent
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        (event.post |> Maybe.map .id |> Maybe.withDefault "")
                        |> Task.attempt GotEventDeleteResult
                    )

                Just (ConfirmOccasionDelete occasion event host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Events.deleteRemovedOccasions
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        { event
                            | occasions =
                                event.occasions
                                    |> List.filter (\other -> (other.post |> Maybe.map .id) /= (occasion.post |> Maybe.map .id))
                        }
                        |> Task.attempt GotOccasionDeleteResult
                    )

                Just (ConfirmNewAnonymousRsvp occasionId host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Task.perform (\_ -> NewAnonymousRsvpConfirmed occasionId host) (Task.succeed ())
                    )

                Just (ConfirmUserDelete user host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Users.deleteUser
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        user
                        |> Task.attempt (GotUserDeleteResult user host)
                    )

                Just (ConfirmPhoneDelete _ host) ->
                    case RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host of
                        Just account ->
                            ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                            , Users.updateUser model.accounts
                                ( Just account.userId, host )
                                account.userId
                                (\freshUser -> { freshUser | phone = Nothing })
                                |> Task.attempt (GotPhoneDeleteResult host)
                            )

                        Nothing ->
                            ( { model | panels = { panels | confirmingDeleteFor = Nothing } }, Cmd.none )

                Just (ConfirmEmailDelete _ host) ->
                    case RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host of
                        Just account ->
                            ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                            , Users.updateUser model.accounts
                                ( Just account.userId, host )
                                account.userId
                                (\freshUser -> { freshUser | email = Nothing })
                                |> Task.attempt (GotEmailDeleteResult host)
                            )

                        Nothing ->
                            ( { model | panels = { panels | confirmingDeleteFor = Nothing } }, Cmd.none )

                Just (ConfirmOccasionSyncDestinationDelete occasion eventSyncDestinationId _ host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Events.deleteOccasionSyncDestination
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        (occasion.post |> Maybe.map .id |> Maybe.withDefault "")
                        eventSyncDestinationId
                        |> Task.attempt (GotOccasionSyncDestinationDeleteResult host)
                    )

                Just (ConfirmPostSyncDestinationDelete post syncDestinationId _ host) ->
                    ( { model | panels = { panels | confirmingDeleteFor = Nothing } }
                    , Posts.deletePostSyncDestination
                        model.accounts
                        ( RellmAccounts.enabledRellmAccountForServer model.accounts.accounts host |> Maybe.map .userId, host )
                        post.id
                        syncDestinationId
                        |> Task.attempt (GotPostSyncDestinationDeleteResult host)
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotSyncSourceDeleteResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotSyncSourceDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotLinkPreviewImagesDeleteResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotLinkPreviewImagesDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotOccasionSyncDestinationDeleteResult _ (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotOccasionSyncDestinationDeleteResult _ (Err _) ->
            ( model, Cmd.none )

        -- Purely a page-level signal (see `ConfirmNewAnonymousRsvp`) -- nothing for Shared itself to do.
        NewAnonymousRsvpConfirmed _ _ ->
            ( model, Cmd.none )

        GotPostSyncDestinationDeleteResult _ (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotPostSyncDestinationDeleteResult _ (Err _) ->
            ( model, Cmd.none )

        GotPostDeleteResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotPostDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotFederatedPostDeleteResult (Ok maybeAccountsPanelMsg) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotFederatedPostDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotEventDeleteResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotEventDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotOccasionDeleteResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( accountsPanelModel, accountsPanelCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }, Cmd.map AccountsPanelMsg accountsPanelCmd )

        GotOccasionDeleteResult (Err _) ->
            ( model, Cmd.none )

        GotUserDeleteResult deletedUser host (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ( refreshedAccounts, refreshCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- Removes `deletedUser` from `refreshedAccounts.accounts` too,
                -- if it's known locally at all -- not just the *enabled*
                -- account for `host` (an Admin deleting a different user's
                -- account they'd disabled here, e.g. after banning them,
                -- should still drop that now-dangling account -- there's no
                -- reason to keep offering to sign back into a user that no
                -- longer exists). Checking every account on `host` rather
                -- than only the enabled one is what makes this also cover
                -- the self-delete case (the deleted account was, by
                -- definition, the one the viewer just acted as), the same
                -- way a manual "remove account"
                -- (`UI.deleteConfirmationModal`'s `ConfirmAccountDelete`)
                -- would.
                ( accountsPanelModel, accountsPanelCmd ) =
                    case refreshedAccounts.accounts |> List.filter (\account -> account.server == host && account.userId == deletedUser.id) |> List.head of
                        Just account ->
                            AccountsPanel.update req (AccountsPanel.RemoveAccountClicked (RellmAccounts.rellmAccountId account)) refreshedAccounts

                        Nothing ->
                            ( refreshedAccounts, Cmd.none )
            in
            ( { model | accounts = accountsPanelModel }
            , Cmd.batch [ Cmd.map AccountsPanelMsg refreshCmd, Cmd.map AccountsPanelMsg accountsPanelCmd ]
            )

        GotUserDeleteResult _ _ (Err _) ->
            ( model, Cmd.none )

        GotPhoneDeleteResult host (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( refreshedAccounts, refreshCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                -- Not necessarily the *focused* account (this same result also lands from
                -- `Components.Pages.UserProfilePage`'s own "Delete Phone", which has no notion of a
                -- focused Accounts Panel account at all) -- found by `host`/`userId` instead, same
                -- as `GotUserDeleteResult`'s own account-list cleanup just above.
                mergedAccountsList : List RellmAccount
                mergedAccountsList =
                    case refreshedAccounts.accounts |> List.filter (\a -> a.server == host && a.userId == updatedUser.id) |> List.head of
                        Just account ->
                            RellmAccounts.upsertRellmAccount { account | phone = updatedUser.phone } refreshedAccounts.accounts

                        Nothing ->
                            refreshedAccounts.accounts

                -- Clears any stale edit/verification state for that account's own nested "Contact
                -- Methods" item too, if it happens to be the one currently focused in the Accounts
                -- Panel.
                clearedContactMethods : Maybe RellmAccounts.RellmContactMethods
                clearedContactMethods =
                    case refreshedAccounts.focusedAccount of
                        Just focused ->
                            if focused.server == host && focused.userId == updatedUser.id then
                                refreshedAccounts.focusedAccountContactMethods
                                    |> Maybe.map (\cm -> { cm | phoneEdit = Nothing, phoneVerification = Nothing })

                            else
                                refreshedAccounts.focusedAccountContactMethods

                        Nothing ->
                            refreshedAccounts.focusedAccountContactMethods
            in
            ( { model | accounts = { refreshedAccounts | accounts = mergedAccountsList, focusedAccountContactMethods = clearedContactMethods } }
            , Cmd.map AccountsPanelMsg refreshCmd
            )

        GotPhoneDeleteResult _ (Err _) ->
            ( model, Cmd.none )

        GotEmailDeleteResult host (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            let
                ( refreshedAccounts, refreshCmd ) =
                    case maybeAccountsPanelMsg of
                        Just accountsPanelMsg ->
                            AccountsPanel.update req accountsPanelMsg model.accounts

                        Nothing ->
                            ( model.accounts, Cmd.none )

                mergedAccountsList : List RellmAccount
                mergedAccountsList =
                    case refreshedAccounts.accounts |> List.filter (\a -> a.server == host && a.userId == updatedUser.id) |> List.head of
                        Just account ->
                            RellmAccounts.upsertRellmAccount { account | email = updatedUser.email } refreshedAccounts.accounts

                        Nothing ->
                            refreshedAccounts.accounts

                clearedContactMethods : Maybe RellmAccounts.RellmContactMethods
                clearedContactMethods =
                    case refreshedAccounts.focusedAccount of
                        Just focused ->
                            if focused.server == host && focused.userId == updatedUser.id then
                                refreshedAccounts.focusedAccountContactMethods |> Maybe.map (\cm -> { cm | emailEdit = Nothing })

                            else
                                refreshedAccounts.focusedAccountContactMethods

                        Nothing ->
                            refreshedAccounts.focusedAccountContactMethods
            in
            ( { model | accounts = { refreshedAccounts | accounts = mergedAccountsList, focusedAccountContactMethods = clearedContactMethods } }
            , Cmd.map AccountsPanelMsg refreshCmd
            )

        GotEmailDeleteResult _ (Err _) ->
            ( model, Cmd.none )

        ShowScrollPreserver ->
            ( { model | scrollPreserverVisible = True }
            , Process.sleep 3000 |> Task.perform (\() -> HideScrollPreserver)
            )

        HideScrollPreserver ->
            ( { model | scrollPreserverVisible = False }, Cmd.none )

        UncollapseHome ->
            let
                navAnimationState : NavAnimationState
                navAnimationState =
                    model.navAnimationState
            in
            ( { model | navAnimationState = { navAnimationState | homeCollapsed = False } }, Cmd.none )

        HomeLinkClicked alreadyHome ->
            let
                ( closedModel, closeCmd ) =
                    sharedUpdate req (StarredPanelMsg StarredPanel.CloseStarredPanel) model

                -- Re-clicking Home while already on it doesn't rerun
                -- `Pages.Home_.init` (same route), so `Main.elm`'s `ChangedUrl`
                -- never fires either -- this is the only reliable "just tapped
                -- Home" hook (see `UI.navLink`), hence scrolling to top here.
                ( scrolledModel, scrollCmd ) =
                    if alreadyHome then
                        sharedUpdate req ScrollToTop closedModel

                    else
                        ( closedModel, Cmd.none )

                navAnimationState : NavAnimationState
                navAnimationState =
                    scrolledModel.navAnimationState

                uncollapsedHomeModel : Model
                uncollapsedHomeModel =
                    { scrolledModel
                        | navAnimationState =
                            { navAnimationState | homeCollapsed = False }
                    }
            in
            ( uncollapsedHomeModel, Cmd.batch [ closeCmd, scrollCmd ] )

        ScrollToTop ->
            ( model, Task.perform (\_ -> NoOp) (Dom.setViewport 0 0) )

        NavLinksScrolled position ->
            ( { model
                | navAnimationState =
                    { homeCollapsed = model.navAnimationState.homeCollapsed || position.scrollLeft > 5
                    , scrollLeft = position.scrollLeft
                    , scrollWidth = position.scrollWidth
                    , clientWidth = position.clientWidth
                    }
              }
            , Cmd.none
            )

        NavigateExternal url ->
            ( model, Nav.load url )

        PushNotificationClicked rawUrl ->
            case PushNotificationLink.toInAppPath model.accounts.mainFrontendHost rawUrl of
                Just path ->
                    ( model, Nav.pushUrl req.key (model.basePath ++ path) )

                Nothing ->
                    ( model, Cmd.none )

        WindowResized width height ->
            ( { model | windowSize = { width = width, height = height } }, Cmd.none )

        GotTimeZone name zone ->
            let
                time : SharedTime.Model
                time =
                    model.time

                browserTimeZone : SharedTime.BrowserTimeZone
                browserTimeZone =
                    time.browserTimeZone
            in
            ( { model | time = { time | browserTimeZone = { browserTimeZone | zone = zone, name = name } } }, Cmd.none )

        GotNow now ->
            let
                time : SharedTime.Model
                time =
                    model.time
            in
            ( { model | time = { time | now = now } }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


{-| The window size isn't known until the DOM actually exists to measure --
`Browser.Events.onResize` (see `subscriptions`) only fires on subsequent
changes, so this is what gets `Model.windowSize` its real initial value.
-}
getInitialWindowSizeCmd : Cmd Msg
getInitialWindowSizeCmd =
    Task.perform
        (\viewport -> WindowResized (round viewport.viewport.width) (round viewport.viewport.height))
        Dom.getViewport


{-| The `primaryColor` `Ports.setNavBarColor` should push to the page's
`<meta name="theme-color">` tags -- see `mainServerTheme`'s note on why
`primaryColor` itself (unlike `primaryBgColor`/`primaryAnchorColor`) doesn't
vary with dark/light mode, so this never fires from a `ThemePreferenceClicked`/
`SystemPrefersDarkChanged` alone.
-}
navBarColorCmd : Model -> Model -> Cmd Msg
navBarColorCmd before after =
    let
        colorOf : Model -> String
        colorOf model_ =
            (AccountsPanel.mainServerTheme (effectiveDarkMode model_) model_.accounts).primaryColor
    in
    if colorOf before /= colorOf after then
        Ports.setNavBarColor (colorOf after)

    else
        Cmd.none


{-| Fires `Ports.hideSplash` the moment `browsingHost`'s own `ServerConfiguration`
request settles -- see `Shared.AccountsPanel.Model.browsingHostConfigResolved`'s
own doc. The `False -> True` guard (rather than firing every time it's `True`)
keeps this a genuine one-shot, same reasoning as `AccountsPanel.finishStartupUnit`'s
own guard.
-}
splashHiddenCmd : Model -> Model -> Cmd Msg
splashHiddenCmd before after =
    if not before.accounts.browsingHostConfigResolved && after.accounts.browsingHostConfigResolved then
        Ports.hideSplash ()

    else
        Cmd.none


themePreferenceLabel : ThemePreference -> String
themePreferenceLabel pref =
    case pref of
        ThemeAuto ->
            "Auto"

        ThemeLight ->
            "Light"

        ThemeDark ->
            "Dark"


themePreferenceToString : ThemePreference -> String
themePreferenceToString pref =
    case pref of
        ThemeAuto ->
            "auto"

        ThemeLight ->
            "light"

        ThemeDark ->
            "dark"


{-| The `/elm`-or-`/`-style mount prefix for a raw (un-normalized) URL path --
see `Model`'s `basePath` field. Only ever `""` or `"/elm"` today (the only two
hosts `backend/src/web/elm_web.rs`/`main_index.rs` serve this app from), found
by checking whether `path` is exactly `/elm` or starts with `/elm/` -- "elm" is
a reserved username (see `validate_username`), so this can never collide with
a real in-app route or federated-user path.
-}
basePathFromPath : String -> String
basePathFromPath path =
    if path == "/elm" || String.startsWith "/elm/" path then
        "/elm"

    else
        ""


{-| Whether the app should currently render in dark mode: the theme the page's own server forces (see
`forcedDarkMode`), if any, otherwise the user's own preference, resolving `Auto` against the last-known
system preference.
-}
effectiveDarkMode : Model -> Bool
effectiveDarkMode model =
    case forcedDarkMode model of
        Just dark ->
            dark

        Nothing ->
            case model.theme.preference of
                ThemeAuto ->
                    model.theme.systemPrefersDark

                ThemeLight ->
                    False

                ThemeDark ->
                    True


{-| The theme the page's server (`mainFrontendHost`) forces via its `CustomCSSConfiguration`'s
`force_light_theme`/`force_dark_theme`: `Just True` for dark, `Just False` for light, `Nothing` if it forces
neither. It overrides the user's Auto/Light/Dark setting (whose toggles are then disabled -- see
`UI.themeToggle`), because a custom stylesheet may only work on one kind of background, and the colors derived
from a server's brand (`primaryAnchorColor`, `navAnchorColor`, ...) are chosen to contrast with it. An
in-progress Custom CSS "Preview" (`AccountsPanel.Model.customCssPreview`) counts, so previewing a stylesheet
previews its forced theme too. If both flags are somehow set (the server rejects that), light wins.
-}
forcedDarkMode : Model -> Maybe Bool
forcedDarkMode model =
    let
        config : Maybe Proto.Rellm.CustomCSSConfiguration
        config =
            case model.accounts.customCssPreview of
                Just preview ->
                    Just preview

                Nothing ->
                    model.accounts.servers
                        |> List.filter (\server -> server.frontendHost == model.accounts.mainFrontendHost)
                        |> List.head
                        |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customCssConfiguration)
    in
    case config of
        Just c ->
            if c.forceLightTheme then
                Just False

            else if c.forceDarkTheme then
                Just True

            else
                Nothing

        Nothing ->
            Nothing


{-| What `Ports.setTheme` should currently put on `<html data-theme>`: the forced theme, if there is one,
otherwise the user's own preference (`"auto"` leaves it to `prefers-color-scheme`). The persisted preference
(`Ports.persistThemePreference`) is always the user's own, never the forced value.
-}
appliedTheme : Model -> String
appliedTheme model =
    case forcedDarkMode model of
        Just True ->
            "dark"

        Just False ->
            "light"

        Nothing ->
            themePreferenceToString model.theme.preference


{-| Re-applies `appliedTheme` whenever it changes -- i.e. when the server's forced theme changes: its
configuration loads or is saved, or a Custom CSS preview starts or stops.
-}
themeCmd : Model -> Model -> Cmd Msg
themeCmd before after =
    if appliedTheme before /= appliedTheme after then
        Ports.setTheme (appliedTheme after)

    else
        Cmd.none


themePreferenceFromString : String -> ThemePreference
themePreferenceFromString s =
    case s of
        "light" ->
            ThemeLight

        "dark" ->
            ThemeDark

        _ ->
            ThemeAuto


nextThemePreference : ThemePreference -> ThemePreference
nextThemePreference pref =
    case pref of
        ThemeAuto ->
            ThemeLight

        ThemeLight ->
            ThemeDark

        ThemeDark ->
            ThemeAuto


{-| Strips `basePath` off `url.path`, so `Gen.Route.fromUrl` can parse it as
if the app were served from `/` -- see `Main.elm`, which calls this on every
`Url` before it touches routing.
-}
normalizeUrl : String -> Url -> Url
normalizeUrl basePath url =
    if basePath == "" then
        url

    else if url.path == basePath then
        { url | path = "/" }

    else if String.startsWith (basePath ++ "/") url.path then
        { url | path = String.dropLeft (String.length basePath) url.path }

    else
        url


{-| The browser's local `Time.Zone`, DST-aware -- unlike plain `Time.here`
(which just snapshots `new Date().getTimezoneOffset()` for the _current_
instant into a fixed-offset `Time.customZone` with no era table, so every
other instant it's ever asked to convert -- e.g. an `Occasion` months
away, on the other side of a DST transition -- gets rendered with today's
offset instead of its own). This instead reads the browser's actual IANA
zone name (e.g. "America/New\_York", via `elm/time`'s `Time.getZoneName`)
and looks up its real transition history/future in
`justinmimbs/timezone-data`, so `Components.Events.occasionWhenText`/
`siblingOccasionWhenText` show a recurring weekly event's fixed local time
(e.g. "6-7PM") as the same "6-7PM" on both sides of a DST change, rather
than drifting an hour. Falls back to plain `Time.here` if the zone name
can't be read or isn't in `timezone-data` (e.g. an unusual environment
`Intl` doesn't cover) -- never fails outright.
-}
getBrowserZone : Task.Task x ( String, Time.Zone )
getBrowserZone =
    TimeZone.getZone
        |> Task.onError (\_ -> Time.here |> Task.map (\zone -> ( "", zone )))


{-| Hosts whose "usable right now" state differs between `before` and `after`
-- either their signed-in account (see `RellmAccounts.enabledRellmAccountForServer`,
e.g. logging into/switching accounts on a server, signing out) or whether
their `Server` itself is enabled (`ToggleServerEnabled` -- which also disables
its accounts, but not for a server with none signed into it, so that flip
needs checking on its own). Tells `Shared.StarredPanel.refreshHosts`
which servers' cached starred `Post`s might now be wrong -- a starred post's
visibility can depend on which account fetched it, and an unavailable
server's shouldn't be fetched/shown at all (see
`Components.ServerDependentView.availableServer`) -- and so need
clearing/refetching.
-}
starredPostsRefreshHosts : AccountsPanel.Model -> AccountsPanel.Model -> List String
starredPostsRefreshHosts before after =
    let
        dedupe : List String -> List String
        dedupe list =
            List.foldl
                (\host acc ->
                    if List.member host acc then
                        acc

                    else
                        host :: acc
                )
                []
                list

        hosts : List String
        hosts =
            dedupe
                ((before.accounts |> List.map .server)
                    ++ (after.accounts |> List.map .server)
                    ++ (before.servers |> List.map .frontendHost)
                    ++ (after.servers |> List.map .frontendHost)
                )

        identity : AccountsPanel.Model -> String -> ( Maybe String, Maybe Bool )
        identity model_ host =
            ( RellmAccounts.enabledRellmAccountForServer model_.accounts host
                |> Maybe.map RellmAccounts.rellmAccountId
            , RellmServers.rellmServerForHost model_.servers host
                |> Maybe.map .enabled
            )
    in
    hosts |> List.filter (\host -> identity before host /= identity after host)
