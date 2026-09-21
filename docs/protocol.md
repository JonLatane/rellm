# Protocol Documentation
<a name="top"></a>

## Table of Contents

- [rellm.proto](#rellm-proto)
    - [Rellm](#rellm-Rellm)
  
- [authentication.proto](#authentication-proto)
    - [AccessTokenRequest](#rellm-AccessTokenRequest)
    - [AccessTokenResponse](#rellm-AccessTokenResponse)
    - [CreateAccountRequest](#rellm-CreateAccountRequest)
    - [CreateThirdPartyRefreshTokenRequest](#rellm-CreateThirdPartyRefreshTokenRequest)
    - [ExpirableToken](#rellm-ExpirableToken)
    - [LoginRequest](#rellm-LoginRequest)
    - [RefreshTokenMetadata](#rellm-RefreshTokenMetadata)
    - [RefreshTokenResponse](#rellm-RefreshTokenResponse)
    - [ResetPasswordRequest](#rellm-ResetPasswordRequest)
    - [UserRefreshTokensResponse](#rellm-UserRefreshTokensResponse)
  
- [visibility_moderation.proto](#visibility_moderation-proto)
    - [Moderation](#rellm-Moderation)
    - [Visibility](#rellm-Visibility)
  
- [permissions.proto](#permissions-proto)
    - [Permission](#rellm-Permission)
  
- [users.proto](#users-proto)
    - [ContactMethod](#rellm-ContactMethod)
    - [ContactMethodVerification](#rellm-ContactMethodVerification)
    - [Follow](#rellm-Follow)
    - [GetUsersRequest](#rellm-GetUsersRequest)
    - [GetUsersResponse](#rellm-GetUsersResponse)
    - [Membership](#rellm-Membership)
    - [User](#rellm-User)
    - [VerifyContactMethodRequest](#rellm-VerifyContactMethodRequest)
  
    - [UserListingType](#rellm-UserListingType)
  
- [media.proto](#media-proto)
    - [Author](#rellm-Author)
    - [GetMediaRequest](#rellm-GetMediaRequest)
    - [GetMediaResponse](#rellm-GetMediaResponse)
    - [Media](#rellm-Media)
    - [MediaMetadata](#rellm-MediaMetadata)
    - [MediaReference](#rellm-MediaReference)
    - [MediaSize](#rellm-MediaSize)
  
    - [MediaConversion](#rellm-MediaConversion)
  
- [messages.proto](#messages-proto)
    - [GetMessagesRequest](#rellm-GetMessagesRequest)
    - [GetMessagesResponse](#rellm-GetMessagesResponse)
    - [GetPushSubscriptionStatusRequest](#rellm-GetPushSubscriptionStatusRequest)
    - [GetPushSubscriptionStatusResponse](#rellm-GetPushSubscriptionStatusResponse)
    - [MarkMessagesReadRequest](#rellm-MarkMessagesReadRequest)
    - [MarkMessagesReadResponse](#rellm-MarkMessagesReadResponse)
    - [Message](#rellm-Message)
    - [MessageRead](#rellm-MessageRead)
    - [MessagingGroup](#rellm-MessagingGroup)
    - [PushSubscription](#rellm-PushSubscription)
    - [RegisterPushSubscriptionRequest](#rellm-RegisterPushSubscriptionRequest)
    - [SendMessageRequest](#rellm-SendMessageRequest)
    - [UnregisterPushSubscriptionRequest](#rellm-UnregisterPushSubscriptionRequest)
  
    - [MessageListingType](#rellm-MessageListingType)
  
- [posts.proto](#posts-proto)
    - [DeletePostSyncDestinationRequest](#rellm-DeletePostSyncDestinationRequest)
    - [GetGroupPostsRequest](#rellm-GetGroupPostsRequest)
    - [GetGroupPostsResponse](#rellm-GetGroupPostsResponse)
    - [GetPostsRequest](#rellm-GetPostsRequest)
    - [GetPostsResponse](#rellm-GetPostsResponse)
    - [GroupPost](#rellm-GroupPost)
    - [Post](#rellm-Post)
    - [SyncPostRequest](#rellm-SyncPostRequest)
    - [UserPost](#rellm-UserPost)
  
    - [PostContext](#rellm-PostContext)
    - [PostListingType](#rellm-PostListingType)
    - [PostMediaLayout](#rellm-PostMediaLayout)
  
- [events.proto](#events-proto)
    - [AnonymousAttendee](#rellm-AnonymousAttendee)
    - [DeleteOccasionSyncDestinationRequest](#rellm-DeleteOccasionSyncDestinationRequest)
    - [Event](#rellm-Event)
    - [EventAttendance](#rellm-EventAttendance)
    - [EventAttendances](#rellm-EventAttendances)
    - [EventInfo](#rellm-EventInfo)
    - [GetEventAttendancesRequest](#rellm-GetEventAttendancesRequest)
    - [GetEventsRequest](#rellm-GetEventsRequest)
    - [GetEventsResponse](#rellm-GetEventsResponse)
    - [Occasion](#rellm-Occasion)
    - [OccasionInfo](#rellm-OccasionInfo)
    - [OccasionRsvpInfo](#rellm-OccasionRsvpInfo)
    - [SyncOccasionRequest](#rellm-SyncOccasionRequest)
    - [TimeFilter](#rellm-TimeFilter)
    - [UserAttendee](#rellm-UserAttendee)
  
    - [AttendanceStatus](#rellm-AttendanceStatus)
    - [EventListingType](#rellm-EventListingType)
  
- [groups.proto](#groups-proto)
    - [GetGroupsRequest](#rellm-GetGroupsRequest)
    - [GetGroupsResponse](#rellm-GetGroupsResponse)
    - [GetMembersRequest](#rellm-GetMembersRequest)
    - [GetMembersResponse](#rellm-GetMembersResponse)
    - [Group](#rellm-Group)
    - [Member](#rellm-Member)
  
    - [GroupListingType](#rellm-GroupListingType)
  
- [server_configuration.proto](#server_configuration-proto)
    - [BirdConfig](#rellm-BirdConfig)
    - [ClusterConductorState](#rellm-ClusterConductorState)
    - [ClusterResourceLimit](#rellm-ClusterResourceLimit)
    - [ClusterResourceLock](#rellm-ClusterResourceLock)
    - [ClusterResources](#rellm-ClusterResources)
    - [CustomHomePage](#rellm-CustomHomePage)
    - [CustomNavigationTab](#rellm-CustomNavigationTab)
    - [CustomNavigationTabSet](#rellm-CustomNavigationTabSet)
    - [EventSettings](#rellm-EventSettings)
    - [ExternalCDNConfig](#rellm-ExternalCDNConfig)
    - [FeatureSettings](#rellm-FeatureSettings)
    - [FreeClusterResourcesRequest](#rellm-FreeClusterResourcesRequest)
    - [LockClusterResourcesRequest](#rellm-LockClusterResourcesRequest)
    - [LockClusterResourcesResponse](#rellm-LockClusterResourcesResponse)
    - [MarketSettings](#rellm-MarketSettings)
    - [MediaSettings](#rellm-MediaSettings)
    - [PostSettings](#rellm-PostSettings)
    - [ServerColors](#rellm-ServerColors)
    - [ServerConfiguration](#rellm-ServerConfiguration)
    - [ServerInfo](#rellm-ServerInfo)
    - [ServerLogo](#rellm-ServerLogo)
    - [StripeConfig](#rellm-StripeConfig)
    - [TelnyxConfig](#rellm-TelnyxConfig)
    - [TwilioConfig](#rellm-TwilioConfig)
    - [WebPushConfig](#rellm-WebPushConfig)
  
    - [AuthenticationFeature](#rellm-AuthenticationFeature)
    - [CalendarDisplayMode](#rellm-CalendarDisplayMode)
    - [ClusterResource](#rellm-ClusterResource)
    - [NavigationTab](#rellm-NavigationTab)
    - [NavigationTabStyle](#rellm-NavigationTabStyle)
    - [PrivateUserStrategy](#rellm-PrivateUserStrategy)
    - [VerificationAPI](#rellm-VerificationAPI)
    - [WebUserInterface](#rellm-WebUserInterface)
  
- [federation.proto](#federation-proto)
    - [FacebookAuthConfig](#rellm-FacebookAuthConfig)
    - [FederatedAccount](#rellm-FederatedAccount)
    - [FederatedServer](#rellm-FederatedServer)
    - [FederationInfo](#rellm-FederationInfo)
    - [GetServiceVersionResponse](#rellm-GetServiceVersionResponse)
    - [MastodonServer](#rellm-MastodonServer)
    - [XTwitterAuthConfig](#rellm-XTwitterAuthConfig)
  
- [sync.proto](#sync-proto)
    - [BlueskyAccount](#rellm-BlueskyAccount)
    - [DeleteSyncDestinationRequest](#rellm-DeleteSyncDestinationRequest)
    - [DeleteSyncSourceRequest](#rellm-DeleteSyncSourceRequest)
    - [FacebookPage](#rellm-FacebookPage)
    - [GetSyncDestinationsResponse](#rellm-GetSyncDestinationsResponse)
    - [GetSyncSourcesResponse](#rellm-GetSyncSourcesResponse)
    - [InstagramAccount](#rellm-InstagramAccount)
    - [MastodonAccount](#rellm-MastodonAccount)
    - [SyncDestination](#rellm-SyncDestination)
    - [SyncDestinationStatus](#rellm-SyncDestinationStatus)
    - [SyncSource](#rellm-SyncSource)
    - [ThreadsAccount](#rellm-ThreadsAccount)
    - [XTwitterAccount](#rellm-XTwitterAccount)
  
- [ai_providers.proto](#ai_providers-proto)
    - [AIModel](#rellm-AIModel)
    - [AIProvider](#rellm-AIProvider)
    - [AIProviderGrant](#rellm-AIProviderGrant)
    - [AnthropicCredentials](#rellm-AnthropicCredentials)
    - [DeleteAIProviderRequest](#rellm-DeleteAIProviderRequest)
    - [DigitalOceanCredentials](#rellm-DigitalOceanCredentials)
    - [GeminiCredentials](#rellm-GeminiCredentials)
    - [GenerateMediaRequest](#rellm-GenerateMediaRequest)
    - [GetAIProvidersResponse](#rellm-GetAIProvidersResponse)
    - [GrantAIProviderRequest](#rellm-GrantAIProviderRequest)
    - [OpenAICredentials](#rellm-OpenAICredentials)
    - [RevokeAIProviderRequest](#rellm-RevokeAIProviderRequest)
  
    - [AIModelCapability](#rellm-AIModelCapability)
  
- [market.proto](#market-proto)
    - [AIGrantPurchaseDetails](#rellm-AIGrantPurchaseDetails)
    - [AIGrantSubscriptionDetails](#rellm-AIGrantSubscriptionDetails)
    - [FulfillmentNote](#rellm-FulfillmentNote)
    - [GetMarketProductsRequest](#rellm-GetMarketProductsRequest)
    - [GetMarketProductsResponse](#rellm-GetMarketProductsResponse)
    - [GetMarketSubscriptionsRequest](#rellm-GetMarketSubscriptionsRequest)
    - [GetMarketSubscriptionsResponse](#rellm-GetMarketSubscriptionsResponse)
    - [MakeMarketPurchaseRequest](#rellm-MakeMarketPurchaseRequest)
    - [MakeMarketPurchaseResponse](#rellm-MakeMarketPurchaseResponse)
    - [MarketPayment](#rellm-MarketPayment)
    - [MarketPaymentMethod](#rellm-MarketPaymentMethod)
    - [MarketProduct](#rellm-MarketProduct)
    - [MarketPurchase](#rellm-MarketPurchase)
    - [MarketRefund](#rellm-MarketRefund)
    - [MarketRefundMethod](#rellm-MarketRefundMethod)
    - [MarketSubscription](#rellm-MarketSubscription)
    - [MediaStoragePurchaseDetails](#rellm-MediaStoragePurchaseDetails)
    - [MediaStorageSubscriptionDetails](#rellm-MediaStorageSubscriptionDetails)
    - [PermissionsAccessPurchaseDetails](#rellm-PermissionsAccessPurchaseDetails)
    - [PermissionsAccessSubscriptionDetails](#rellm-PermissionsAccessSubscriptionDetails)
    - [RellmHostingPurchaseDetails](#rellm-RellmHostingPurchaseDetails)
    - [RellmHostingSubscriptionDetails](#rellm-RellmHostingSubscriptionDetails)
  
    - [FulfillmentStatus](#rellm-FulfillmentStatus)
    - [GetMarketSubscriptionsRequestType](#rellm-GetMarketSubscriptionsRequestType)
    - [PurchasePeriod](#rellm-PurchasePeriod)
    - [PurchaseType](#rellm-PurchaseType)
  
- [Scalar Value Types](#scalar-value-types)



<a name="rellm-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## rellm.proto


 

 

 


<a name="rellm-Rellm"></a>

### Rellm
[Jump to the gRPC API?](#grpc-api)

[Rellm](https://github.com/JonLatane/rellm) is a social media protocol with support for Users (and Follows), Media, Posts, Events, Groups, and Messages. It is designed to be federated, 
but does not require federation to be a useful next-gen forum type solution.
It is designed to be used with a variety of frontends, including web, mobile, and desktop applications. It interoperates across numerous ports, protocols, and formats, including
gRPC, HTTP, HTTPS, and ICS/iCal, and is designed to link with SMTP via Stalwart (and other SMTP servers/providers), Facebook Page APIs for post ing Events, and more.
Essentially, your server is your own customizable, self-contained social network.

Rellm is designed to be easy to run and deploy yourself with a [2 minute setup with Homebrew](#2-minute-startup-with-homebrew) and [3 minute setup on Linux](#3-minute-startup-on-linux),
[images](https://hub.docker.com/r/jonlatane/rellm/tags) on [DockerHub](https://hub.docker.com/r/jonlatane/rellm_preview_generator/tags) and deployment to your K8s clusters available via
a simple but powerful `Makefile`-based design language.

### Ports &amp; Protocols
Rellm servers interact across several ports:
* [gRPC (27707)](#grpc-api) - The main Rellm gRPC API. This is the primary port for all Rellm clients. It may or may not be TLS-enabled (443).
     * Clients are expected to negotiate the gRPC host via the [`backend_host` HTTP endpoint (see below)](#http-based-client-host-negotiation-for-external-cdns) on port 80/443.
* [HTTP (80, 8000, 27705), HTTPS (443)](#http-endpoints) - The main Rellm HTTP API. This is used for some endpoints, including media upload/download, and for negotiating the gRPC host.
     * Port 443 will serve up a secure HTTPS server. If it fails to startup, Rellm handles this gracefully and degrades to plain HTTP.
     * Port 80 will serve up either an unsecured set of Rellm&#39;s HTTP endpoints, or a redirect to the HTTPS/443 server if that one launched successfully.
     * Port 8000 *always* serves up an unsecured Rellm UI, in case something goes horribly wrong with 80 and 443. It can probably not be exposed in your load balancer/to the web.
     * Port 27705 is an unsecured HTTP server meant for communication with other non-web facing services on your computer or in your cluster. It should not be exposed to the web.
         * Currently this just has an `/email` endpoint. It is designed for [email/SMTP support via an integration with Stalwart](https://github.com/JonLatane/rellm/tree/main/deploys/email).

#### Cross-Protocol Federation
Rellm clients can translate content from other federated protocols into the same
[`Post`](#rellm-Post)/[`Author`](#rellm-Author) shapes used everywhere else in the app --
entirely client-side, with no RPCs of their own. The server&#39;s only role is admin configuration:
[`FederationInfo`](#rellm-FederationInfo) tells clients which instances/apps are safe or
expected to pull from. There is no server-to-server proxying or bridging involved - this follows
the same &#34;the client does the merging&#34; pattern as [`FederatedServer`](#rellm-FederatedServer),
just reaching across a protocol boundary instead of a Rellm-to-Rellm one. It&#39;s also
one-directional (reading in, not posting out) - publishing a Rellm [`Post`](#rellm-Post) *to*
Mastodon or Bluesky is a separate feature, [`SyncDestination`](#rellm-SyncDestination).

##### Mastodon/ActivityPub
A client can browse any Mastodon instance&#39;s local public timeline
(`GET /api/v1/timelines/public?local=true`) with zero configuration, since it&#39;s already a public,
unauthenticated REST endpoint - no [`MastodonServer`](#rellm-MastodonServer) entry is needed
just to *read* public posts.

Connecting an actual Mastodon *account* is a heavier flow, since Mastodon has no single central
OAuth authority the way Facebook/X do - every instance is its own separate OAuth provider. A
server admin registers an app on a given instance ahead of time
(`FederationInfo.mastodon_servers`, a [`MastodonServer`](#rellm-MastodonServer) carrying that
instance&#39;s `app_id`/`app_secret`), and only then can a user on that instance complete the OAuth
popup &#43; PKCE flow to connect their own account. `MastodonServer.configured_by_default`/
`pinned_by_default` let an admin recommend a given instance be auto-browsed the first time a
client visits this server - see those fields&#39; own docs for the current relationship between the
two.

##### BlueSky/AT Protocol
Unlike Mastodon, AT Protocol has no &#34;local instance timeline&#34; concept at all - every Personal
Data Server (PDS) only ever serves its own users&#39; own repos, so there is nothing equivalent to
browse anonymously. Cross-protocol federation with Bluesky therefore always requires a connected
account: a handle and an [App Password](https://bsky.app/settings/app-passwords) (not OAuth --
AT Protocol has no per-client app-registration step the way Mastodon/Facebook/X require), used to
call `com.atproto.server.createSession` and then the account&#39;s own
`app.bsky.feed.getTimeline`. Because there&#39;s no server-side app to register, there is no
`BlueskyServer` config type mirroring [`MastodonServer`](#rellm-MastodonServer) - nothing about
connecting a Bluesky account is admin-configurable the way a Mastodon OAuth app is.

### API Design Notes
#### Moderation and Visibility
Rellm APIs are designed to support [`Moderation`](#rellm-Moderation) and [`Visibility`](#rellm-Visibility) controls at the level of individual entities. However, to keep things
DRY, moderation and visibility controls are only implemented for [`User`](#rellm-User)s, [`Media`](#rellm-Media), [`Group`](#rellm-Group)s, and [`Post`](#rellm-Post)s.

[`Event`](#rellm-Event)s and future [`Post`](#rellm-Post)-like types simply use the same implementation as their contained [`Post`](#rellm-Post)s. The intent here is to maximize
both shared code and implementation robustness.

#### Composition Over Inheritance
Rellm&#39;s APIs are designed using composition over inheritance. For instance, an [`Event`](#rellm-Event) contains
a [`Post`](#rellm-Post) rather than extending it. This pattern fits well all the way from the data model (very boring, safe, and normalized), 
through Rust code implementing APIs, to both functional React code and more-OOP Flutter code equally well.

#### Predictable Atomicity
The use of composition over inheritance also means that Rellm APIs can be *predictably* non-atomic based on their compositional structure.
For instance, [`UpdatePost`](#grpc-api-UpdatePost) is fully atomic.

[`UpdateEvent`](#grpc-api-UpdateEvent), however, is non-atomic. Given that an [`Event`](#rellm-Event) has a [`Post`](#rellm-Post) and many [`Occasion`](#rellm-Occasion)s,
[`UpdateEvent`](#grpc-api-UpdateEvent) is implemented as a composition of four other RPCs - each independently callable and individually atomic --
run in a fixed order: [`UpdateEventDetails`](#grpc-api-UpdateEventDetails) (which itself first updates the [`Event`](#rellm-Event)&#39;s own [`Post`](#rellm-Post)
atomically, literally calling the [`UpdatePost`](#grpc-api-UpdatePost) RPC), then [`CreateNewOccasions`](#grpc-api-CreateNewOccasions),
[`UpdateOccasions`](#grpc-api-UpdateOccasions), and finally [`DeleteRemovedOccasions`](#grpc-api-DeleteRemovedOccasions).
Create must run before Delete so that a request which both drops an old [`Occasion`](#rellm-Occasion) and adds a new one never transiently
leaves the [`Event`](#rellm-Event) with zero Occasions.

Because moderation/visibility lives at the [`Post`](#rellm-Post) level, and [`UpdateEventDetails`](#grpc-api-UpdateEventDetails) runs first, this means that a developer error in the
later [`Occasion`](#rellm-Occasion)-processing steps cannot prevent visibility and moderation changes from being made in Events, even if there are errors elsewhere.
This should prove a robust pattern for any future entities intended to be shareable at a Group level with visibility and
moderation controls (for instance, `Sheet`, `SharedExpenseReport`, `SharedCalendar`, etc.). The entire architecture should promote this
approach to predictable atomicity.

### Core Types
Rellm&#39;s data model centers around a handful of top-level types, most of which carry their own
[`Visibility`](#rellm-Visibility) and [`Moderation`](#rellm-Moderation) state and can be organized into
[`Group`](#rellm-Group)s.

#### ServerConfiguration
Rellm incorporates server configuration, including fairly deep customization of the end-user UI/UX, as perhaps its *most* primitive type.
[`ServerConfiguration`](#rellm-ServerConfiguration) is unlike most of the highly-normalized, minimalist types in the Rellm protocol,
and is more like a document than a row in a database. (That said, every [`ServerConfiguration`](#rellm-ServerConfiguration) change *is* a row in a database, meaning
reverting broken configurations is easy.)

Any client using the Rellm protocol is basically expected to follow a flow of &#34;get service version, then [`ServerConfiguration`](#rellm-ServerConfiguration),
then worry about auth, then finally about retrieving anything else.&#34;

##### Server Info and Theme
[`ServerInfo`](#rellm-ServerInfo) (`server_info`) carries the server&#39;s public-facing identity: `name`,
`short_name`, `description`, `privacy_policy` and `media_policy` text shown during account creation and on the
`/about` page, a multi-size [`ServerLogo`](#rellm-ServerLogo) (separate light/dark, square/wide media IDs), a
[`ServerColors`](#rellm-ServerColors) scheme (primary/navigation accents plus author/admin/moderator name
colors), and `web_user_interface` choosing which UI a browser is served (React/Tamagui by default, or the Elm
SPA/Flutter Web alternatives).

##### Custom Tabs
[`CustomNavigationTabSet`](#rellm-CustomNavigationTabSet) (`custom_tabs`) lets a server admin override the Elm
UI&#39;s default navigation. `home` (a [`CustomHomePage`](#rellm-CustomHomePage)) replaces `/` itself - a
predefined tab or a specific Post, optionally with Posts pinned above its content and/or an Events strip shown
above it; `tabs` (repeated [`CustomNavigationTab`](#rellm-CustomNavigationTab)) replaces the
`EVENTS_TAB`/`POSTS_TAB`/`PEOPLE_TAB`/`ABOUT_TAB` set entirely, each pinned to its own custom URL (`path`). Each
`CustomNavigationTab` targets either a predefined [`NavigationTab`](#rellm-NavigationTab), a Post ID, or
(path-only) a user profile, with its own emoji- or Media-backed icon and optional title override. `path` is
fully live - the Elm SPA actually routes it (`Pages.UsernameOrCustomTab_`), not just previews it - except for
the built-in `/events`, `/posts`, `/people`, and `/about` paths themselves, which stay reserved for their own
matching predefined tab and can&#39;t be remapped elsewhere.

##### Anonymous, Default, and Basic User Permission Sets
Three [`Permission`](#rellm-Permission) lists set the server&#39;s baseline access, each enforced independently of
any per-User/per-Group grants: `anonymous_user_permissions` (what a logged-out visitor may do - only the
`VIEW_*` permissions are valid here), `default_user_permissions` (what every new account starts with), and
`basic_user_permissions` (the superset a user holding `GRANT_BASIC_PERMISSIONS` may hand out to others). Granting
`GLOBAL_PUBLIC` as a feature&#39;s `default_visibility` (see `people_settings`/`group_settings`/`post_settings`/
`event_settings` below) requires the matching `PUBLISH_*_GLOBALLY` permission to actually be present in
`default_user_permissions`.

##### Federation Settings
[`FederationInfo`](#rellm-FederationInfo) (`federation_info`) is where all federation and social-sync
credentials live.

###### Other Rellm servers
`servers` (repeated [`FederatedServer`](#rellm-FederatedServer)) recommends other Rellm hosts to clients,
each optionally `configured_by_default` (client should enable/configure it automatically) and/or
`pinned_by_default` (client should pin its Events/Posts alongside the &#34;main&#34; server&#39;s).

###### Mastodon/ActivityPub servers
`mastodon_servers` (repeated [`MastodonServer`](#rellm-MastodonServer)) plays a similar role to
`servers` above, but for Mastodon instances instead of other Rellm servers - see
[Cross-Protocol Federation](#cross-protocol-federation) for the client-side feature this backs.
Unlike a real `FederatedServer`, though, an entry here is *not* required just to browse an
instance&#39;s public timeline read-only - that&#39;s already a public, unauthenticated Mastodon REST
endpoint any client can call directly. It&#39;s only needed to let a user *connect their own*
Mastodon account (OAuth &#43; PKCE), since Mastodon has no single central OAuth authority the way
Facebook/X do: every instance is its own separate OAuth provider, so an admin has to register an
app (`app_id`/`app_secret`, the latter *never* serialized to the client) on each instance
individually before its users can connect. `configured_by_default`/`pinned_by_default` mirror
`FederatedServer`&#39;s own fields, but govern that anonymous browsing instead: whether clients should
auto-add the instance to their browsed list the first time they visit this server, not whether an
account gets auto-connected (that always requires the user&#39;s own explicit OAuth consent).

A Mastodon instance functions like a much thinner version of a federated Rellm server in the
UI: its public posts appear in the same multi-server feed, translated into Rellm&#39;s own
[`Post`](#rellm-Post) shape, but it has no equivalent of Rellm&#39;s Events, Groups, Media
library, or People/Follows - just posts and their authors.

###### Facebook API Keys
`facebook_auth_config` (a [`FacebookAuthConfig`](#rellm-FacebookAuthConfig), `app_id`/`app_secret`) registers
this server&#39;s Facebook App, enabling users to connect Facebook Page and Instagram Business
[`SyncDestination`](#rellm-SyncDestination)s. `app_secret` is write-only/never serialized back to clients;
admins set/rotate it via [`ConfigureServer`](#grpc-api-ConfigureServer) (i.e. the same admin UI form that
manages the rest of [`ServerConfiguration`](#rellm-ServerConfiguration)) - the secret is simply never echoed
back in subsequent [`GetServerConfiguration`](#grpc-api-GetServerConfiguration) responses.

###### X (Twitter) API Keys
`x_twitter_auth_config` (an [`XTwitterAuthConfig`](#rellm-XTwitterAuthConfig), `client_id`/`client_secret`)
registers this server&#39;s X Developer App, enabling users to connect X [`SyncDestination`](#rellm-SyncDestination)s
- until set, X SyncDestinations fail with `x_twitter_app_not_configured`. `client_secret` is write-only/never
serialized back to clients, set/rotated the same way as the Facebook API keys above.

##### Web Push Configuration
[`WebPushConfig`](#rellm-WebPushConfig) (`web_push_config`) holds the server&#39;s VAPID keypair for Web Push
notifications: `public_vapid_key` is served to clients so they can subscribe, while `private_vapid_key` signs
outgoing pushes and is *never* serialized to clients - like the federation secrets above, admins set/rotate it
via [`ConfigureServer`](#grpc-api-ConfigureServer), not by editing the database directly.

##### CDN Configuration
[`ExternalCDNConfig`](#rellm-ExternalCDNConfig) (`external_cdn_config`) enables running Rellm behind a CDN
(e.g. Cloudflare&#39;s &#34;CNAME HTTPS Proxy&#34;): when set, the unsecured HTTP server (port 80) stops redirecting to
HTTPS and instead serves the Tamagui Web client directly, with `frontend_host`/`backend_host` telling the web
client which domains to use instead of `window.location.hostname` (Tamagui web only, for now). `secure_media`
plus its `media_ipv4_allowlist`/`media_ipv6_allowlist` are a (TODO, not yet enforced) way to restrict media
downloads on the unsecured server to the CDN&#39;s own IP ranges; `cdn_grpc` is a further (TODO) mode that would move
the gRPC server itself onto port 443 to ride along Cloudflare&#39;s gRPC support.

#### User
A [`User`](#rellm-User) is a Rellm account: username, real name, bio, avatar, contact methods, and
[`Permission`](#rellm-Permission)s, plus counts (followers, posts, events, etc.) and federation info (see
[Federated Profiles](#federated-profiles) above). A lighter-weight [`Author`](#rellm-Author) (just ID, username,
avatar, real name, permissions) is embedded on [`Post`](#rellm-Post)s, [`Message`](#rellm-Message)s, and similar
content types instead of a full [`User`](#rellm-User), to keep those payloads small.

##### Follows
A [`Follow`](#rellm-Follow) is one [`User`](#rellm-User) following another, optionally subject to the target&#39;s moderation
(i.e. approval). Mutual follows make two users &#34;friends.&#34; Follows also drive the `FOLLOWING_POSTS`/`FOLLOWING_EVENTS`
listing types and `LIMITED`-visibility content.

##### Memberships
A [`Membership`](#rellm-Membership) is a [`User`](#rellm-User)&#39;s membership (or pending join request/invitation)
in a [`Group`](#rellm-Group), tracking the user&#39;s [`Permission`](#rellm-Permission)s within the group plus separate group-side and user-side [`Moderation`](#rellm-Moderation)
(for join-approval flows). Returned as part of [`User`](#rellm-User)/[`Group`](#rellm-Group) payloads, and via [`Member`](#rellm-Member) when listing a Group&#39;s members.

##### SyncSources
While Federation is a first-class feature of Rellm, a [`User`](#rellm-User) can also own many
[`SyncSource`](#rellm-SyncSource)s - server-owned external origins to sync [`Post`](#rellm-Post)s in from other
fediverse and less-open platforms, via a `oneof configuration` naming which source type it is: an iCal
subscription URL (`configuration.ics_subscription_url`, syncing in [`Event`](#rellm-Event)s/
[`Occasion`](#rellm-Occasion)s), or an RSS/Atom subscription URL (`configuration.rss_subscription_url`/
`configuration.atom_subscription_url`, syncing in plain [`Post`](#rellm-Post)s). Every kind of synced content is
tagged via its own `Post.sync_source` - an [`Event`](#rellm-Event)&#39;s own Post, each of its
[`Occasion`](#rellm-Occasion)s&#39; own Post, or a plain synced Post - since a single source can back many
synced Posts but each Post has at most one source it came from; see the Event and Post sections below for how
these attach. A background job re-pulls each source on its own `sync_interval_seconds` cadence, recomputing
`event_count`/`occasion_count` (iCal) or `post_count` (RSS/Atom) on every sync.

Sources are managed via [`GetSyncSources`](#grpc-api-GetSyncSources), [`CreateSyncSource`](#grpc-api-CreateSyncSource)
(requires `SYNC_EVENTS_FROM_ICS`/`SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM` - whichever matches
the source&#39;s own configuration - or Admin), [`UpdateSyncSource`](#grpc-api-UpdateSyncSource), and
[`DeleteSyncSource`](#grpc-api-DeleteSyncSource).

See also: [`SyncDestination`](#rellm-SyncDestination)

###### iCal
`configuration.ics_subscription_url` is a plain iCal (`.ics`) subscription URL. The background job fetches and
parses it on each sync, creating/updating one [`Event`](#rellm-Event) (and one [`Occasion`](#rellm-Occasion)
per occurrence) per iCal `VEVENT` - each occurrence&#39;s own Post is keyed by `(sync_source_id, sync_source_uid,
sync_source_recurrence_anchor)`, the iCal UID plus that occurrence&#39;s stable identity within its series (its own
start time, or its original scheduled time if since rescheduled) - and recomputing `event_count`/
`occasion_count`. An `Occasion`&#39;s `sync_missing_since` is set the first time it stops appearing in
the feed, letting the owner decide whether that means it should be deleted. No auth/credentials are supported
yet - only public iCal URLs.

###### RSS
`configuration.rss_subscription_url` is a plain RSS 2.0 subscription URL. The background job fetches and parses
it on each sync, creating/updating one plain [`Post`](#rellm-Post) per RSS `&lt;item&gt;` - each Post is keyed by
`(sync_source_id, sync_source_uid)`, `sync_source_uid` being the item&#39;s own `&lt;guid&gt;` (or a hash of its `&lt;link&gt;`
if it has none) - and recomputing `post_count`. Unlike iCal, a `&lt;item&gt;` that stops appearing in the feed is left
alone rather than pruned: RSS feeds are commonly truncated to their most recent N items by the publisher, so
&#34;no longer in the feed&#34; doesn&#39;t mean &#34;was retracted&#34;. No auth/credentials are supported yet - only public RSS
URLs.

###### Atom
`configuration.atom_subscription_url` is a plain Atom subscription URL, behaving identically to RSS (above) --
one plain [`Post`](#rellm-Post) per `&lt;entry&gt;`, keyed by `(sync_source_id, sync_source_uid)` with `sync_source_uid`
being the entry&#39;s own `&lt;id&gt;`, recomputing `post_count`, missing entries left alone rather than pruned. RSS and
Atom feeds are parsed via the same underlying library into one unified shape, so both formats share this exact
behavior - pick whichever a given source actually publishes.

##### SyncDestinations
A [`User`](#rellm-User) can also own many [`SyncDestination`](#rellm-SyncDestination)s - user-owned external
targets to push [`Occasion`](#rellm-Occasion)s and [`Post`](#rellm-Post)s out to (see the Event and
Post sections below for how these attach), via a `oneof configuration` naming which platform it is. This is a
many-to-many relationship: it&#39;s each [`Occasion`](#rellm-Occasion) or [`Post`](#rellm-Post) (not,
say, the parent [`Event`](#rellm-Event)) that syncs out, and each may push to several destinations at once,
tracked per-destination via the repeated `Occasion.sync_destinations`/`Post.sync_destinations` (each a
[`SyncDestinationStatus`](#rellm-SyncDestinationStatus), carrying the destination&#39;s resulting post ID/URL and
last-synced time). Destinations are pushed to on demand rather than synced in bulk on an interval, so
`synced_occasion_count`/`synced_post_count` are computed with a `COUNT` at request time instead of being
recomputed-and-stored. All API keys for these external platforms are stored in
[`ServerConfiguration`](#rellm-ServerConfiguration)&#39;s `federation_info`.

Destinations are managed via [`GetSyncDestinations`](#grpc-api-GetSyncDestinations),
[`CreateSyncDestination`](#grpc-api-CreateSyncDestination), [`UpdateSyncDestination`](#grpc-api-UpdateSyncDestination),
and [`DeleteSyncDestination`](#grpc-api-DeleteSyncDestination) - each gated on the `SYNC_EVENTS_TO_*`/
`SYNC_POSTS_TO_*` permission pair matching the destination&#39;s own platform (or Admin; see each platform&#39;s own
section below). Actually syncing (or un-syncing) a given [`Occasion`](#rellm-Occasion) or [`Post`](#rellm-Post) to a destination is a separate
step, via [`SyncOccasion`](#grpc-api-SyncOccasion)/
[`DeleteOccasionSyncDestination`](#grpc-api-DeleteOccasionSyncDestination) and
[`SyncPost`](#grpc-api-SyncPost)/[`DeletePostSyncDestination`](#grpc-api-DeletePostSyncDestination), gated the same
way (the `_EVENTS_`/`_POSTS_` half matching which RPC).

See also: [`SyncSource`](#rellm-SyncSource)

###### Facebook
`configuration.facebook_page` (a [`FacebookPage`](#rellm-FacebookPage)) is a connected Facebook Page.
Connecting one requires a short-lived user access token from client-side Facebook Login
(`FacebookPage.short_lived_user_access_token`), which the server exchanges for a long-lived Page access token; the
short-lived token is write-only and never populated back in responses. Gated on `SYNC_EVENTS_TO_FACEBOOK`/
`SYNC_POSTS_TO_FACEBOOK`.

###### Instagram
`configuration.instagram_account` (an [`InstagramAccount`](#rellm-InstagramAccount)) is a connected Instagram
Business/Creator account. Instagram posting is only possible for an account linked to a Facebook Page, so
connecting one reuses the exact same Facebook Login flow/app credentials as Facebook above - the server exchanges
the token for the chosen Page&#39;s access token, then looks up that Page&#39;s linked Instagram Business account
(`instagram_business_account_id`). Unlike Facebook, Instagram&#39;s Graph API has no text-only post type; syncing a
[`Post`](#rellm-Post)/[`Occasion`](#rellm-Occasion) with no attached media fails with `instagram_requires_media`. Gated on
`SYNC_EVENTS_TO_INSTAGRAM`/`SYNC_POSTS_TO_INSTAGRAM`.

###### Mastodon
`configuration.mastodon_account` (a [`MastodonAccount`](#rellm-MastodonAccount)) is a connected Mastodon
account, on any instance the user names (`instance_host`) - there&#39;s no single app to register the way
Facebook/Instagram have one, so connecting one is a user-pasted Personal Access Token
(`MastodonAccount.access_token`, generated on the user&#39;s own instance under Preferences &gt; Development) rather than
an OAuth popup. Gated on `SYNC_EVENTS_TO_MASTODON`/`SYNC_POSTS_TO_MASTODON`.

###### Bluesky
`configuration.bluesky_account` (a [`BlueskyAccount`](#rellm-BlueskyAccount)) is a connected Bluesky (AT
Protocol) account. Connecting one is a user-supplied &#34;App Password&#34; (`BlueskyAccount.app_password`, generated at
Settings &gt; App Passwords - not the account&#39;s main password) rather than an OAuth popup. Gated on
`SYNC_EVENTS_TO_BLUESKY`/`SYNC_POSTS_TO_BLUESKY`.

###### X (Twitter)
`configuration.x_twitter_account` (an [`XTwitterAccount`](#rellm-XTwitterAccount)) is a connected X account. Requires this
server to have a registered X Developer App configured (`FederationInfo.x_twitter_auth_config`) - until an admin
sets one, every RPC touching an [`XTwitterAccount`](#rellm-XTwitterAccount) destination fails with `x_twitter_app_not_configured`. Once
configured, connecting is an OAuth 2.0 Authorization Code &#43; PKCE flow at x.com (`response_type=code`, like
Threads, but with a `code_challenge`/`code_verifier` pair X requires and Threads doesn&#39;t) - the server exchanges
the code for a short-lived access token (2 hour expiry) plus a refresh token, transparently refreshing before
each post. Only image media is uploaded today; video is not yet supported (see `XTwitterAccount`&#39;s own doc).
Gated on `SYNC_EVENTS_TO_X_TWITTER`/`SYNC_POSTS_TO_X_TWITTER`.

###### Threads
`configuration.threads_account` (a [`ThreadsAccount`](#rellm-ThreadsAccount)) is a connected Threads account.
Threads API is a product added to this server&#39;s *existing* Facebook App (see [`FacebookAuthConfig`](#rellm-FacebookAuthConfig)) rather than a
separately-registered app, but its OAuth flow is otherwise its own: authorization happens at threads.net (not
facebook.com) using `response_type=code` rather than Facebook&#39;s implicit `response_type=token`, with no &#34;choose a
Page&#34; step - it directly authorizes the user&#39;s own Threads account. The server exchanges the code for a
short-lived token, then a long-lived one (~60 day expiry, refreshable via `grant_type=th_refresh_token` - not yet
implemented, so a connected destination needs reconnecting after ~60 days). Unlike Instagram, Threads supports
text-only posts. Gated on `SYNC_EVENTS_TO_THREADS`/`SYNC_POSTS_TO_THREADS`.

##### AIProviders
A [`User`](#rellm-User) can also own many [`AIProvider`](#rellm-AIProvider)s -
connections to external AI model APIs (e.g. a Gemini or OpenAI API key) - and grant other users metered access to
them via [`AIProviderGrant`](#rellm-AIProviderGrant)s. See `ai_providers.proto` and the
AIProvider section below. Which models are actually available, and what each can do
([`AIModelCapability`](#rellm-AIModelCapability)), is a hand-maintained catalog (no provider exposes a stable
&#34;list models&#34; API to build this from at request time) - see
[`backend/src/logic/ai_model_catalog.rs`](https://github.com/JonLatane/rellm/blob/main/backend/src/logic/ai_model_catalog.rs)
on GitHub for the actual source of truth.

#### AIProvider
An [`AIProvider`](#rellm-AIProvider) is a user-owned connection to an external AI model API (e.g. a
Gemini API key), via a `oneof provider` naming which service it is - structurally similar to
[`SyncDestination`](#rellm-SyncDestination)/[`SyncSource`](#rellm-SyncSource), but rather than pushing/pulling
content, it&#39;s metered *access* an owner can share out to other users of this server. As with
[`SyncDestination`](#rellm-SyncDestination)&#39;s platform credentials, the actual API key is write-only - accepted
on [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider)
but never populated back in a response.

Providers are managed via [`GetAIProviders`](#grpc-api-GetAIProviders),
[`CreateAIProvider`](#grpc-api-CreateAIProvider) (requires `CREATE_AI_PROVIDERS`, or Admin),
[`UpdateAIProvider`](#grpc-api-UpdateAIProvider), and [`DeleteAIProvider`](#grpc-api-DeleteAIProvider)
- each gated self-or-Admin, the same shape as [`SyncDestination`](#rellm-SyncDestination)&#39;s RPCs.

##### Gemini
`provider.gemini_credentials` (a [`GeminiCredentials`](#rellm-GeminiCredentials)) is a Google Gemini API
connection (`ai.google.dev/gemini-api`), used for image generation/editing (e.g. generating Event posters) via
its Interactions API.

##### OpenAI
`provider.openai_credentials` (an [`OpenAICredentials`](#rellm-OpenAICredentials)) is an OpenAI API connection
(`platform.openai.com/docs/guides/image-generation`), used for image generation/editing via its Images API (GPT
Image models).

##### Anthropic
`provider.anthropic_credentials` (an [`AnthropicCredentials`](#rellm-AnthropicCredentials)) is reserved for a
connected Anthropic API, but **not yet creatable** - Anthropic doesn&#39;t offer an image generation API, so it&#39;s
defined only for forward compatibility.

##### DigitalOcean
`provider.digitalocean_credentials` (a [`DigitalOceanCredentials`](#rellm-DigitalOceanCredentials)) is a
DigitalOcean Gradient AI Platform / Serverless Inference connection (`docs.digitalocean.com/products/inference`),
used for image *generation only* (no editing - DigitalOcean&#39;s Serverless Inference API has no
`/v1/images/edits`-equivalent endpoint) via its OpenAI-Images-API-shaped `/v1/images/generations` endpoint (GPT
Image and Stable Diffusion models, re-hosted under DigitalOcean&#39;s own billing).

##### AIProviderGrants
A provider&#39;s owner may share metered access to it with other users via
[`AIProviderGrant`](#rellm-AIProviderGrant)s, each carrying a `tokens_remaining` budget for that grantee.
Granted/reset via [`GrantAIProvider`](#grpc-api-GrantAIProvider) (upserted on the unique
`(ai_provider_id, grantee)` pair - granting again *resets*, rather than adds to, `tokens_remaining`) and
removed via [`RevokeAIProvider`](#grpc-api-RevokeAIProvider). Unlike every other RPC pair in this section,
these two are **owner-only, with no Admin override** - an Admin may manage the provider record itself, but only
its owner may hand out access to it.

#### Rellm&#39;s Market
Rellm&#39;s Market (`market.proto`) is this server&#39;s storefront - a small, Stripe-backed marketplace an admin
stocks with up to twelve [`MarketProduct`](#rellm-MarketProduct)s (one offering type times one billing period
each) that any user can buy. Four offering types exist today ([`PurchaseType`](#rellm-PurchaseType)):
`PURCHASE_TYPE_MEDIA_STORAGE` (raises the buyer&#39;s `User.media_storage_limit_bytes`),
`PURCHASE_TYPE_AI_GRANTS` (grants/resets an [`AIProviderGrant`](#rellm-AIProviderGrant) against one of the
server operator&#39;s [`AIProvider`](#rellm-AIProvider)s), `PURCHASE_TYPE_RELLM_HOSTING` (bills the buyer for
the server operator to stand up a new Rellm instance on a domain of their choosing - provisioned by hand, not
automated; the admin&#39;s own `/market/fulfillment` page, backed by
`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN` and
[`UpdateMarketSubscription`](#grpc-api-UpdateMarketSubscription), tracks these orders -
[`RellmHostingSubscriptionDetails`](#rellm-RellmHostingSubscriptionDetails)&#39;s own `fulfillment_status`/
`fulfillment_notes` fields), and `PURCHASE_TYPE_PERMISSIONS_ACCESS` (grants the buyer a fixed set of `Permission`s, e.g.
pay-gating `SYNC_EVENTS_TO_FACEBOOK`). Every purchase gets a [`MarketSubscription`](#rellm-MarketSubscription) --
even a one-time ([`PurchasePeriod`](#rellm-PurchasePeriod) `PURCHASE_PERIOD_INDEFINITE`) purchase, so it&#39;s still
cancelable and still carries the same per-type fulfillment tracking (e.g. `fulfillment_status`/`fulfillment_notes` above)
a recurring one does; it just never gets a `renews_at`, so it never actually bills again. A recurring
`PURCHASE_PERIOD_ANNUAL`/`PURCHASE_PERIOD_MONTHLY` subscription&#39;s `billing_history` accumulates one
[`MarketPurchase`](#rellm-MarketPurchase) per renewal; an indefinite one&#39;s stays at exactly one.

Products are listed via [`GetMarketProducts`](#grpc-api-GetMarketProducts) (unauthenticated; admins
additionally see delisted ones) and managed via
[`CreateMarketProduct`](#grpc-api-CreateMarketProduct)/[`UpdateMarketProduct`](#grpc-api-UpdateMarketProduct)
(both Admin-only; a [`MarketProduct`](#rellm-MarketProduct)&#39;s `type`/`period` are immutable once created).
Buying one is a two-step, webhook-settled flow: [`MakeMarketPurchase`](#grpc-api-MakeMarketPurchase) starts a
Stripe Checkout Session and returns its URL to redirect the buyer to - no
[`MarketPurchase`](#rellm-MarketPurchase)/[`MarketSubscription`](#rellm-MarketSubscription) is created yet, so
an abandoned checkout leaves nothing behind. Only once Stripe confirms payment (a
`checkout.session.completed` webhook delivery) does the server create the
[`MarketPurchase`](#rellm-MarketPurchase)/[`MarketSubscription`](#rellm-MarketSubscription) and apply its
entitlement. A recurring [`MarketSubscription`](#rellm-MarketSubscription) renews itself thereafter via
off-session charges against the payment method saved on that first checkout - no further action from the
buyer - until either a renewal charge fails or the buyer/admin calls
[`CancelMarketSubscription`](#grpc-api-CancelMarketSubscription), either of which sets `canceled_at`. The
entitlement itself stays in effect until whichever is later of `renews_at`/`canceled_at` - once both have
passed, the `renew_market_subscriptions` background job revokes it (reverts `media_storage_limit_bytes` to
`ServerConfiguration.media_settings.default_media_allocation_bytes`, or removes the granted `Permission`s,
depending on `type`) and sets `service_terminated_at`. A user&#39;s own MarketSubscriptions (never anyone
else&#39;s) are listed via [`GetMarketSubscriptions`](#grpc-api-GetMarketSubscriptions), and also travel along
on [`User`](#rellm-User) itself (`User.market_subscriptions`) the same way `ai_models`/`sync_sources` do.
Stripe credentials for all of this live in `ServerConfiguration.stripe_config` (a
[`StripeConfig`](#rellm-StripeConfig)), Admin-only like `twilio_config`/`bird_config`.

#### Media
[`Media`](#rellm-Media) represents an uploaded (or server-generated) photo or video. Unlike other types, Media
content itself is *not* served over gRPC - it&#39;s uploaded/downloaded via plain HTTP (`POST`/`GET /media`) - while
its metadata (content type, name, visibility, moderation) is managed like any other Rellm type. Other messages
(like `User.avatar`, `Group.avatar`, and `Post.media`) reference Media via the lightweight [`MediaReference`](#rellm-MediaReference) type.

#### Post
[`Post`](#rellm-Post) is Rellm&#39;s fundamental content/building-block type: it&#39;s what actually carries a
title/link/content body, visibility, and moderation, and is reused (via [`PostContext`](#rellm-PostContext)) as the backing data for
replies, [`Event`](#rellm-Event)s, and [`Occasion`](#rellm-Occasion)s alike. Posts can be replied to (threaded via
`reply_to_post_id`), cross-posted to [`Group`](#rellm-Group)s ([`GroupPost`](#rellm-GroupPost)), and shared directly with users ([`UserPost`](#rellm-UserPost)).

##### GroupPosts
A [`GroupPost`](#rellm-GroupPost) is the cross-posting of a [`Post`](#rellm-Post) into a [`Group`](#rellm-Group), carrying the group-specific
moderation status and who shared it, separately from the Post&#39;s own (author-set) visibility/moderation.

##### UserPosts
A [`UserPost`](#rellm-UserPost) is a &#34;direct share&#34; of a [`Post`](#rellm-Post) to a [`User`](#rellm-User) (see also `DIRECT`
[`Visibility`](#rellm-Visibility)). Currently unused/unimplemented.

##### SyncDestinations
A [`Post`](#rellm-Post) may also be synced (cross-posted) out to a user-owned
[`SyncDestination`](#rellm-SyncDestination) (e.g. a connected Facebook Page), the same mechanism
[`Occasion`](#rellm-Occasion)s use (see below) - each Post may push to several destinations at once, tracked via the
repeated `Post.sync_destinations` (each a [`SyncDestinationStatus`](#rellm-SyncDestinationStatus)).

#### Event
An [`Event`](#rellm-Event) is a wrapper for *at least two* [`Post`](#rellm-Post)s. It always has its own top-level [`Post`](#rellm-Post)
(`PostContext.EVENT`, holding the event&#39;s overall title/description) *and* it must have at least one
[`Occasion`](#rellm-Occasion) (see below), each of which in turn must have its own [`Post`](#rellm-Post)
(`PostContext.OCCASION`, carrying that Occasion&#39;s start/end time, [`Location`](#rellm-Location), and optional per-Occasion
title/link/content override). So the smallest possible Event already backs 2 Posts, and events with recurring/multiple
Occasions back one Post per Occasion beyond that.

##### Occasions
An [`Occasion`](#rellm-Occasion) is the actual time-boxed occurrence of an [`Event`](#rellm-Event) -
it carries the `starts_at`/`ends_at` timestamps and optional [`Location`](#rellm-Location) that the parent [`Event`](#rellm-Event) itself does not have.
An [`Event`](#rellm-Event) with zero Occasions is meaningless (no time or place to attach to), so every [`Event`](#rellm-Event) must have at least one.

    - **EventAttendances**: An [`EventAttendance`](#rellm-EventAttendance) (an &#34;RSVP&#34;) tracks one attendee&#39;s status
    (`INTERESTED`, `REQUESTED`, `GOING`, `NOT_GOING`) for a specific [`Occasion`](#rellm-Occasion). Attendees may be logged-in [`User`](#rellm-User)s
    or anonymous (tracked via [`AnonymousAttendee`](#rellm-AnonymousAttendee) plus an `auth_token`), and are subject to their own [`Moderation`](#rellm-Moderation),
    independent of the Event&#39;s/Occasion&#39;s own Post moderation.

    - **SyncSource**: It&#39;s actually the parent [`Event`](#rellm-Event) (not the [`Occasion`](#rellm-Occasion)) that can be synced *in* from a
    user-owned [`SyncSource`](#rellm-SyncSource) (e.g. an iCal subscription). The relationship is
    1:(0 or 1): a single source can back many synced [`Event`](#rellm-Event)s, but each [`Event`](#rellm-Event) has *at most one* source it came from
    (`Event.sync_source` is a single optional field, not repeated).

    - **SyncDestinations**: Conversely, it&#39;s each [`Occasion`](#rellm-Occasion) (not the parent [`Event`](#rellm-Event)) that syncs *out* to
    [`SyncDestination`](#rellm-SyncDestination)s (e.g. connected Facebook Pages) - the same mechanism [`Post`](#rellm-Post)s use
    (see above). Unlike [`SyncSource`](#rellm-SyncSource), this is the outlier&#39;s counterpart - a many-to-many relationship: each
    Occasion may push to several destinations at once, tracked per-destination via the repeated
    `Occasion.sync_destinations` (each a [`SyncDestinationStatus`](#rellm-SyncDestinationStatus)), carrying
    the destination&#39;s resulting post ID/URL and last-synced time.

#### Group
A [`Group`](#rellm-Group) organizes [`User`](#rellm-User)s, [`Post`](#rellm-Post)s, and [`Event`](#rellm-Event)s together under shared visibility, moderation,
and permission defaults.

##### Memberships
A [`Membership`](#rellm-Membership) is a [`User`](#rellm-User)&#39;s membership (or pending join request/invitation)
in a [`Group`](#rellm-Group), tracking the user&#39;s [`Permission`](#rellm-Permission)s within the group plus separate group-side and user-side [`Moderation`](#rellm-Moderation)
(for join-approval flows). Returned as part of [`User`](#rellm-User)/[`Group`](#rellm-Group) payloads, and via [`Member`](#rellm-Member) when listing a Group&#39;s members.

##### GroupPosts
A [`GroupPost`](#rellm-GroupPost) is the cross-posting of a [`Post`](#rellm-Post) into a [`Group`](#rellm-Group), carrying the group-specific
moderation status and who shared it, separately from the Post&#39;s own (author-set) visibility/moderation.

#### Message
[`Message`](#rellm-Message) is Rellm&#39;s &#34;low trust&#34; messaging/email system, meant to let strangers on a server
make first contact (e.g. via email, with no account required) before moving to a more trusted channel. Admins have
open access to all Messages on a server.

Email support in Messages comes from the [Stalwart integration](#post-email-stalwart-email-integration) and requires 
a Stalwart server to be running and configured to forward emails to the Rellm server. Rellm provides tooling
to do this automatically, but it is completely optional.

##### MessagingGroup
A [`MessagingGroup`](#rellm-MessagingGroup) is the set of participants in a Message conversation. Every [`Message`](#rellm-Message)
belongs to one; if a client wasn&#39;t a visible recipient (e.g. they were BCC&#39;ed), the [`Message`](#rellm-Message) they receive omits it.

### Authentication
Rellm uses a standard OAuth2 flow (over gRPC) for authentication, with rotating `access_token`s and `refresh_token`s (both [`ExpirableToken`s](#rellm-ExpirableToken)).
Authenticated calls require an `access_token` in request metadata to be included / directly as the value of the
`authorization` header (no `Bearer ` prefix).
The `ExpirableToken` type allows clients to know ahead of time when their `access_token` and `refresh_token` are about to expire.

First, before *any* authentication is done, you should [resolve your backend host](#http-based-client-host-negotiation-for-external-cdns-get-backend_host),
and check its [`GetServiceVersion`](#grpc-api-GetServiceVersion) and [`GetServerConfiguration`](#grpc-api-GetServerConfiguration) RPCs.
Check whether you have the `CREATE_ACCOUNT` and/or `LOGIN` [`AuthenticationFeature`](#rellm-AuthenticationFeature)s in your [`ServerConfiguration`](#rellm-ServerConfiguration).

Next, use the [`CreateAccount`](#grpc-api-CreateAccount) or [`Login`](#grpc-api-Login) RPCs to fetch (and store) an initial
`refresh_token` and `access_token`. Clients should use the `access_token` until it expires,
then use the `refresh_token` to call the [`AccessToken`](#grpc-api-AccessToken) RPC for a new one. (The [`AccessToken`](#grpc-api-AccessToken) RPC
may, at random, also return a new `refresh_token`. If so, it should immediately replace the old
one in client storage.)

#### Federated Authentication
tl;dr: Lets you sign in to the `jon@bullcity.social` user on `jonline.io`, without ever entering your `bullcity.social`
credentials on `jonline.io`.

Elm-only feature (`frontends/elm-spa`) letting a user sign in to one Rellm server using an account they already
have (or are willing to create) on a *different* Rellm server, without either backend ever seeing a plaintext
token that isn&#39;t its own. It&#39;s pure browser-to-browser: two Elm SPA page routes
([`/auth/to/...`](#authtopublic_keyrequesting_host-sending-side) and
[`/auth/from/...`](#authfromencrypted_account_auth_tokens-receiving-side)) exchange
an encrypted pair of tokens via a full-page redirect; no gRPC/HTTP endpoint on either backend is involved beyond
the [`Login`](#grpc-api-Login) RPC itself (plus [`GetCurrentUser`](#grpc-api-GetCurrentUser) on the receiving side,
to hydrate everything else - see step 6).

1. Say a user is on `jonline.io`, adding a new account, and enters `bullcity.social` as the server. Since that
isn&#39;t the current host, the Accounts panel offers a &#34;Sign in via bullcity.social&#34; button instead of (or alongside)
a normal username/password form.
2. Clicking it does a full-page navigation to `bullcity.social`, carrying `jonline.io`&#39;s ECDH public key (freshly
generated in-browser and persisted for this purpose) and its own hostname in the URL: `/auth/to/{public_key}@jonline.io`.
3. `bullcity.social` shows its own sign-in form (or, if already signed in there, a badge to reuse that session),
plus a &#34;Sign back in here&#34; checkbox, checked by default.
4. The user authenticates via the [`Login`](#grpc-api-Login) RPC. This always issues a *fresh* `refresh_token`/
`access_token` pair, reserved purely for transfer back to `jonline.io` - it&#39;s never used to sign the browser into
`bullcity.social` itself. If &#34;Sign back in here&#34; is checked, a **second**, independent [`Login`](#grpc-api-Login)
call also runs, so `bullcity.social` gets its own local session too, and the two servers never end up sharing a
token pair. (Hence &#34;1-2 refresh tokens.&#34;)
5. Only `bullcity.social`&#39;s hostname and that fresh `refresh_token`/`access_token` pair are JSON-encoded and
encrypted to `jonline.io`&#39;s public key from step 2 (ephemeral ECDH &#43; HKDF &#43; AES-GCM - see below) - nothing else
about the account travels in the payload. The browser is then redirected back to `jonline.io` at
`/auth/from/{ciphertext}`.
6. `jonline.io` decrypts the payload with the private key it generated in step 2, calls
[`GetCurrentUser`](#grpc-api-GetCurrentUser) against `bullcity.social` with the decrypted `access_token` to hydrate
the rest of the account (user ID, username, avatar, permissions, etc. straight from `bullcity.social` itself
rather than trusting a client-supplied copy of them), then adds it to its Accounts panel and navigates the user
onward - no confirmation step. Either way, the one-time keypair generated in step 2 is discarded and a fresh one
generated in its place, so it can&#39;t be reused for a second transfer.

See the two [Web UI](#authtopublic_keyrequesting_host-and-authfromencrypted_account_auth_tokens-receiving-side)
page routes below for the exact URL/crypto shape.

### Federation
Whereas other federated social networks (e.g. ActivityPub) have both client-server and server-server APIs,
Rellm only has client-server APIs. While server-to-server communication is possible, nothing but some
&#34;nice to have&#34; features require it, so it is not used.

#### Federated Servers
Rellm servers can recommend other servers to clients with the `federation_info` field (a [`FederationInfo` message](#rellm-FederationInfo)) in [`ServerConfiguration`](#rellm-ServerConfiguration).
Clients can use this information to discover other servers, or users can add new servers manually.
Note that, at least for web clients, this means everything is subject to CORS. In the future, Rellm will
allow CORS to be configured in a &#34;strict&#34; mode, so someone else&#39;s Rellm server cannot be used to access your server&#39;s data
unless you explicitly allow it.

#### Federated Profiles
Rellm users can federate with users on any other Rellm server. This works by two-way verification:
For example, Jon has the user [`jonline.io/jon`](https://jonline.io/jon), [`oakcity.social/jon`](https://oakcity.social/jon),
and [`bullcity.social/jon`](https://bullcity.social/jon) associated with one another. 
The UI will only show federated profiles if *both use profiles* have federated with one another.

This mechanism also allows users to link multiple profiles on the same server together. For instance, [`bullcity.social/jon`](https://bullcity.social/jon)
and [`bullcity.social/openmic`](https://bullcity.social/openmic) are linked together, but [`bullcity.social/openmic`](https://bullcity.social/openmic)
isn&#39;t linked to [`jonline.io/jon`](https://jonline.io/jon) or [`oakcity.social/jon`](https://oakcity.social/jon).

Federated profiles are managed via the `federated_profiles` field (a `repeated` [`FederatedAccount`](#rellm-FederatedAccount)) in the [`User`](#rellm-User) message.

#### Federated Browsing
Rellm&#39;s protocols and UI are designed to work together to present a seamless UX for content from many types of communities. Users can add/remove servers
in a way that gives them control, transparency and trust. Meanwhile, server owners get extreme customization and useful integrations with social media
platforms.

#### Federated Messaging
Rellm&#39;s Elm Messaging UI is generally a multi-server federated messenger. The main limitation is that it can only receive push notifications
from one server. (This could be changed with VAPID key sharing, but is part of the VAPID protocol.)

#### Federated Markets
The Elm `/market` page can show more than one server&#39;s Market side by side: the browsed server&#39;s own
(always first) plus any other connected, enabled server whose `ServerConfiguration.market_settings.enabled`
is set (in Accounts panel order after that) - the public, non-secret &#34;is this server&#39;s Market open&#34; signal,
unlike `stripe_config` itself, which stays Admin-only. Each section is fully independent: it lists that
server&#39;s own [`MarketProduct`](#rellm-MarketProduct)s and shows product-management controls only if the
current user is actually an Admin *on that server*.

Unlike Federated Browsing/Profiles/Messaging above, buying is never seamless across servers - Market is the
one place a user must always transact with the target site directly. A product tile for the browsed server
links to its own in-app product page as usual, but a tile for any *other* server links straight to that
server&#39;s own `https://{host}/market/product/{id}` (a real page navigation, not client-side routing), since
[`MakeMarketPurchase`](#grpc-api-MakeMarketPurchase) starts a Stripe Checkout Session scoped to whichever
server the buyer is actually authenticated against, and Stripe&#39;s own `success_url`/`cancel_url` redirect
back to that same server when payment completes.

### HTTP Endpoints
#### Internal HTTP server (27705)
##### `POST /email`: Stalwart Email Integration
Delivery endpoint called by the [Stalwart](https://stalw.art) mail server (see
[`deploys/email`](https://github.com/JonLatane/rellm/tree/main/deploys/email)&#39;s
[README](https://github.com/JonLatane/rellm/blob/main/deploys/email/README.md) for setup/architecture) once it
accepts an inbound message addressed to one of this Rellm instance&#39;s onboarded domains, turning it into a
[`Message`](#rellm-Message). It is **internal-only**: mounted solely on the unsecured 27705 server (never on
80/8000/443), has no authentication of its own, and trusts its caller completely - that trust boundary is
expected to be enforced at the network layer (e.g. a `NetworkPolicy` restricting port 27705 to Stalwart&#39;s pod).

* **Request**: the body is Stalwart&#39;s `data`-stage [MTA Hook](https://stalw.art/docs/mta/filter/mtahooks/) JSON
payload (up to 50 MiB), not a raw MIME stream - only the fields below are read, the rest of Stalwart&#39;s payload
(`context`, `envelope.from`, `message.serverHeaders`, `message.size`, ...) is ignored:
```json
{
  &#34;envelope&#34;: { &#34;to&#34;: [{ &#34;address&#34;: &#34;someone@yourdomain.com&#34; }] },
  &#34;message&#34;: {
    &#34;headers&#34;: [[&#34;Subject&#34;, &#34;Hello&#34;], [&#34;From&#34;, &#34;sender@example.com&#34;], [&#34;To&#34;, &#34;someone@yourdomain.com&#34;]],
    &#34;contents&#34;: &#34;Hello, World!\r\n&#34;
  }
}
```
Recipients come from `envelope.to[].address` - deliberately the SMTP envelope, not the message&#39;s `To`/`Cc`
headers, since that&#39;s the only place Bcc&#39;d recipients show up at all. The message itself is reconstructed by
concatenating `message.headers` (each an unfolded `[name, value]` pair) with `message.contents` across a blank
line, which `mail_parser` then parses as the RFC822 message - Stalwart only splits at the top-level header/body
boundary, so this still captures multipart bodies and attachments intact within `contents`. A body that isn&#39;t
valid JSON in this shape, or that doesn&#39;t reconstruct into a parseable MIME message, returns `400 Bad Request`;
an oversized body returns `413 Payload Too Large`.
* **Recipient resolution**: each envelope address&#39;s local part (before the `@`) is looked up as a username on this
server; addresses that don&#39;t match any user are silently skipped, since Stalwart is expected to have already
confirmed deliverability before calling this endpoint. If none match, the whole message is dropped and the
endpoint returns `404 Not Found`.
* **Storage**: matched recipients become a [`Message`](#rellm-Message) addressed to a
[`MessagingGroup`](#rellm-MessagingGroup) keyed on the `To`/`Cc` recipients only - Bcc&#39;d recipients are excluded
from the group (so they stay invisible to everyone else on the thread) and instead recorded individually as `Bcc`
rows on the [`Message`](#rellm-Message). The [`Message`](#rellm-Message) has no `from_user_id`, since inbound email never has a local sender; its
parsed `from`/`to`/`cc` headers are stored alongside it, and the raw `.eml` is uploaded to the same MinIO store
used for [`Media`](#rellm-Media). Duplicate deliveries of the same `Message-ID` (Stalwart retries on transient failure) reuse the
existing [`Message`](#rellm-Message) row rather than storing/uploading a duplicate.
* **Response**: `200 OK` with a body of `{&#34;action&#34;: &#34;accept&#34;}` on success - Stalwart&#39;s MTA Hook protocol parses
the response *body*, not just the status code, so this has to be the exact shape it expects
(see &lt;https://stalw.art/docs/mta/filter/mtahooks/&gt;) or Stalwart treats the call as a hook failure regardless of
status; combined with the `MtaHook`&#39;s `tempFailOnError: true`, that surfaces to the sending client as a
`451` temp-fail rather than anything indicating the real cause.

#### External HTTP servers (80, 8000, 443)
Note that, if the TLS server on port 443 starts up successfully, the server on port 80
will simply redirect to HTTPS.

The server on port 8000 will always serve up unsecured HTTP. It is up to server admins to block this
port if they find that necessary.

##### `GET /backend_host`: HTTP-based client host negotiation (for external CDNs)
When first negotiating the gRPC connection to a host, say, `jonline.io`, before attempting
to connect to `jonline.io` via gRPC on 27707/443, the client
is expected to first attempt to `GET jonline.io/backend_host` over HTTP (port 80) or HTTPS (port 443)
(depending upon whether the gRPC server is expected to have TLS). If the `backend_host` string resource
is a valid domain, say, `jonline.io.itsj.online`, the client is expected to connect
to `jonline.io.itsj.online` on port 27707/443 instead. To users, the server should still *generally* appear to 
be `jonline.io`. The client can trust `jonline.io/backend_host` to always point to the correct backend host for
`jonline.io`.

This negotiation enables support for external CDNs as frontends. See https://jonline.io/about?section=cdn for
more information about external CDN setup. Developers may wish to review the [React/Tamagui](https://github.com/JonLatane/rellm/blob/main/frontends/tamagui/packages/app/store/clients.ts#L116) 
and [Flutter](https://github.com/JonLatane/rellm/blob/main/frontends/flutter/lib/models/rellm_clients.dart#L26) 
client implementations of this negotiation.

##### `GET /robots.txt`: Robots
Generated on the fly (not a static file) from the request&#39;s `Host` header, publicly cacheable for 1 hour. Always
allows all crawling (`User-agent: * / Allow: /`) and points crawlers at `https://{host}/sitemap.xml`.

##### `GET /sitemap.xml`: Sitemap
Generated on the fly (not a static file) from the request&#39;s `Host` header, publicly cacheable for 1 hour. Lists a
fixed set of top-level, server-wide pages - `/`, `/posts`, `/events`, `/people`, `/about`, `/about_rellm`,
`/flutter`, `/tamagui`, `/elm` - plus any `CustomNavigationTabSet.tabs` paths configured on the server (excluding
the reserved `posts`/`events`/`people`/`about` paths, which are always included above), each qualified with the
request&#39;s `Host`. It also enumerates individual pages: every [`Post`](#rellm-Post) from an unauthenticated [`GetPosts`](#grpc-api-GetPosts) (the same
&#34;first page&#34; an anonymous visitor sees) as `/post/{id}`, and every [`Occasion`](#rellm-Occasion) from an unauthenticated
[`GetEvents`](#grpc-api-GetEvents) starting `EventSettings.calendar_lookback_days` (or 14, if unset) ago as `/event/{occasion_id}`.
It does not (yet) enumerate individual [`User`](#rellm-User) pages.

##### `GET /favicon.ico`: ICO Favicon
Serves the server&#39;s configured logo (`ServerConfiguration.server_info.logo.square_media_id`, a [`Media`](#rellm-Media)
reference) as an `.ico`, publicly cacheable for 12 hours (`must-revalidate`), converting on the fly if the
stored rendition is a `.png`. If no logo is configured, falls back to the bundled Tamagui frontend&#39;s default
favicon instead. Whichever converted rendition of the logo is served, it&#39;s picked in size preference order
Medium, then Small, then Large, then the original upload if none of those conversions exist (favicons are small,
so there&#39;s no reason to prefer a bigger one).

##### `GET /favicon.png`: PNG Favicon
As `GET /favicon.ico` above, but serves (and if necessary converts to) `.png` instead.

##### `POST /media`: Upload Media
See the [Media](#rellm-Media) section for the [`Media`](#rellm-Media) type itself; this is how its bytes actually get in
(an `OPTIONS /media` variant also exists, solely to satisfy CORS preflight requests). *Authenticated* (via
`Authorization` header or a `rellm_access_token` cookie). Requires `Content-Type` and `Filename` headers; the
body is streamed directly to the object store, capped at 250 MiB - note that a larger upload is silently
truncated to that cap rather than rejected, since nothing checks for completeness the way `POST /email` does --
at a path namespaced by uploader and request host (`user/{user_id}@{host}-{username}/{uuid}-{filename}`). A
[`Media`](#rellm-Media) row is created immediately at `GLOBAL_PUBLIC` visibility (video content types also get
a default `video_preview_time_ms`) and its ID returned as plain text - there&#39;s no separate &#34;confirm&#34; step, and
no image/video conversion happens synchronously on this request (see the background media-conversion job).

##### `GET /media/{id}?size={original|small|medium|large}`: Download Media
(An `OPTIONS /media/{id}` variant also exists, solely to satisfy CORS preflight requests.) Publicly downloadable
- **moderation/visibility/permission checks on read are not yet enforced** (a `TODO` in `media_file`&#39;s
implementation), so a [`Media`](#rellm-Media) ID is currently a bearer capability. `size` (default `medium`) selects a converted
rendition, falling back to the original upload if that conversion doesn&#39;t exist. The first request for a given
rendition lazily downloads it from the object store into a local on-disk cache; subsequent requests are served
from that cache. Cacheable for 12 hours (`must-revalidate`).

##### `GET /calendar.ics`: Server Calendar
Rellm events support iCalendar/RFC5545; only public events are included. &#34;Subscribe&#34; to a Rellm server at,
for instance, `https://jonline.io/calendar.ics` to get a calendar of all public events on the server. In the
Tamagui/React frontend, links to these endpoints are provided in the Upcoming Events section of the home page,
the Events page, and the user profile pages for all users with events in the last 3 months (or in the future).

##### `GET /calendar.ics?user_id={id}`: User Calendar
&#34;Subscribe&#34; to a user&#39;s calendar at, for instance, `https://jonline.io/calendar.ics?user_id=CruFm` to get a
calendar of all public events for that user.

##### `GET /rss.xml` / `GET /atom.xml`: Server Posts Feed
The reverse direction of a `SyncSource`&#39;s own RSS/Atom subscription (see the SyncSources section above): serves
Rellm&#39;s own [`Post`](#rellm-Post)s back out as a feed, only public Posts included. &#34;Subscribe&#34; to a Rellm server
at, for instance, `https://jonline.io/rss.xml` (or `/atom.xml`) to get a feed of all public posts on the server,
in whichever of the two formats a given feed reader prefers - both endpoints serve the same underlying Posts.
In the Elm frontend, links to these endpoints are provided next to the Posts page&#39;s own search controls, and on
the home page and user profile pages&#39; embedded posts lists.

##### `GET /rss.xml?user_id={id}` / `GET /atom.xml?user_id={id}`: User Posts Feed
&#34;Subscribe&#34; to a user&#39;s posts at, for instance, `https://jonline.io/rss.xml?user_id=CruFm` (or `/atom.xml?user_id=CruFm`)
to get a feed of all public posts for that user.

### Web UI paths
Rellm serves three web frontends from the same backend: Tamagui (React/Next.js), Elm, and Flutter.

Tamagui and Elm share one page structure (below) and are always *both* reachable, explicitly, at `/tamagui/*`
and `/elm/*` respectively; unprefixed requests (`/`, `/posts`, `/post/{postId}`, etc.) render whichever of the
two the server&#39;s `ServerConfiguration.server_info.web_user_interface` selects (`ELM_SPA` picks Elm; every other
setting, including no preference at all, picks Tamagui). Elm is a genuine single-page app - every Elm-served
path, prefixed or not, resolves to the same `index.html`, with in-app (client-side) routing taking over from
there - whereas Tamagui&#39;s Next.js build is statically exported one HTML file per route, so the server picks
between actual distinct files below, each enriched with server-rendered, per-route social-preview
(`&lt;title&gt;`/`og:*`) tags before being served.

**Flutter does not participate in any of this.** It has no page structure of its own to speak of: no per-route
pages, no server-rendered social-preview metadata, and no unprefixed presence at all - a server configured to
prefer it doesn&#39;t route &#34;/&#34; through the Tamagui/Elm machinery below and then render Flutter, it instead serves
Flutter&#39;s own `index.html` directly, bypassing that machinery entirely. Flutter is otherwise reached only at the
literal `/flutter` and `/flutter/*` paths, which serve its compiled static assets; from there, all further
in-app navigation is handled entirely client-side by Flutter&#39;s own router and is invisible to the server.

The shared Tamagui/Elm page structure, grouped the way the [Elm app&#39;s `Pages`
directory](https://github.com/JonLatane/rellm/tree/main/frontends/elm-spa/src/Pages) is (`{name}` denotes a
dynamic path segment; `[@{host}]` marks where a [federated](#federated-profiles) `{username}@{host}`-style
suffix is accepted for that segment):

#### `/`: Home
The community&#39;s latest activity.

#### `/posts`: Posts
The Posts listing.

##### `/post/{postId}[@{host}]`: Post
An individual [`Post`](#rellm-Post) - including [`Event`](#rellm-Event)/[`Occasion`](#rellm-Occasion) posts and replies, which are [`Post`](#rellm-Post)s
themselves (see [Post](#post) above).

#### `/events`: Events
The Events listing.

#### `/[-._~:/?[]@!$&amp;&#39;()*&#43;,;%=]{postId}`: Short Post/Event URLs
A [`Post`](#rellm-Post) or [`Event`](#rellm-Event)/[`Occasion`](#rellm-Occasion), reached at its own `post.id` prefixed
with any single character a username/custom tab path could never legally start with (see
[`validate_username`](https://github.com/JonLatane/rellm/blob/main/backend/src/rpcs/validations/validate_fields.rs)&#39;s
own reserved-lead-character check) - e.g. `jonline.io/:4rAfoSKAuJo` or `ato.band/~4rAfoSKAuJo`.
This is purely a shorter, friendlier alias for `/post/{postId}[@{host}]` or
`/event/{postId}[@{host}]` (whichever the id turns out to belong to) - it renders exactly that
same content in place, without redirecting the address bar away from the short URL. `#` is
deliberately excluded from the reserved set: URL fragments never reach the server, so they
can&#39;t be used for this.

##### `/event/{postId}[@{host}]`: Event
An individual [`Event`](#rellm-Event), looked up by its own `post.id` or any of its [`Occasion`](#rellm-Occasion)s&#39; `post.id`s.

##### `/event_ai`: AI Event Importer
Tamagui-only, for now - an AI-assisted bulk [`Event`](#rellm-Event) importer. Elm doesn&#39;t have this page yet.

#### `/people`: People
The People listing.

##### `/people/follow_requests`: Follow Requests
The current user&#39;s pending [`Follow`](#rellm-Follow) requests.

##### `/user/{userId}`: Profile
A [`User`](#rellm-User) profile looked up by (stable) user ID.

#### `/{custom_tab_or_username}`: User pages by username, or a custom tab
The same [`User`](#rellm-User) profile (and its Posts/Friends/Followers/Following sub-pages) as `/user/{userId}` above, but
looked up by the current `username` instead - lighter-weight to link to, but less stable than `/user/{userId}`
since a username can change. This single path segment is also the server&#39;s last-resort catch-all, resolved in
order: first any actual matching build asset or other explicit route above (e.g. `/posts`, `/user/{userId}`)
wins outright; then, if none matched, an admin-configured custom tab path (see
[`CustomNavigationTab`](#rellm-CustomNavigationTab).path) - e.g. a band mounting their Events
listing at `/gigs` - wins over a same-named user; only then, last, is it looked up as a plain username. A small
set of reserved names can never be reached this way, only via `/user/{userId}`.

##### `/{username}/posts`: Posts
##### `/{username}/friends`: Friends
##### `/{username}/followers`: Followers
##### `/{username}/following`: Following

#### `/g/{shortname}`: Groups
A [`Group`](#rellm-Group)&#39;s pages. Tamagui-only for now - the Elm frontend doesn&#39;t have Group pages yet.

##### `/g/{shortname}`: Home
##### `/g/{shortname}/posts`: Posts
##### `/g/{shortname}/p/{postId}[@{host}]`: Post
An individual [`Post`](#rellm-Post) cross-posted into the group.

##### `/g/{shortname}/events`: Events
##### `/g/{shortname}/e/{occasionId}[@{host}]`: Event
##### `/g/{shortname}/members`: Members
##### `/g/{shortname}/m/{username}`: Member
An individual [`Member`](#rellm-Member)&#39;s details.

#### `/server/{serverIdentifier}`: Server
Information about a (possibly federated) Rellm server.

#### `/about`, `/about_rellm`: About
This server&#39;s own About page, and a general &#34;what is Rellm&#34; page.

#### `/auth/to/{public_key}@{requesting_host}` and `/auth/from/{encrypted_account_auth_tokens}`: Federated Sign-In
**Elm-only** - unlike everything else in this section, these two paths have no Tamagui equivalent. They&#39;re Elm
SPA pages (served like any other SPA route - under the `/elm` base path when the Elm frontend isn&#39;t the one
mounted at `/`) rather than backend/gRPC handlers, driving the
[Federated Authentication](#federated-authentication) flow entirely in-browser via a pair of full-page redirects
carrying an encrypted payload.

##### `/auth/to/{public_key}@{requesting_host}`: sending side
`Pages.Auth.To.Key_`. Reached only via the cross-origin redirect from step 2 above (built by the *requesting*
origin&#39;s Accounts panel), never linked to directly.
* **Path params**: `{public_key}` is the requesting origin&#39;s ECDH (P-256) public key, raw-exported and
base64url-encoded; `{requesting_host}` is that origin&#39;s own hostname. The two are joined with a literal `@`
(chosen because `@` never appears in the base64url/dot-joined ciphertext the
[`/auth/from`](#authfromencrypted_account_auth_tokens-receiving-side) page below expects, so the split is
unambiguous).
* **Query params**: `start_path` - the app-relative path the user was on when they clicked &#34;Sign in via ...&#34;, so
they can be dropped back there after the round trip. Percent-encoded; passed through unchanged to the eventual
[`/auth/from`](#authfromencrypted_account_auth_tokens-receiving-side) redirect.
* **Behavior**: shows a sign-in form for *this* server (or a &#34;currently signed in as ...&#34; badge, if already
authenticated here), plus a &#34;Sign back in here&#34;/&#34;Also sign in here&#34; checkbox (checked by default). Submitting
calls the [`Login`](#grpc-api-Login) RPC (always a fresh login, never reusing stored tokens) to mint the transfer
tokens; if the checkbox is checked, a second independent [`Login`](#grpc-api-Login) call also signs the browser
into this server locally. `{requesting_host}`&#39;s hostname plus that fresh `refresh_token`/`access_token` pair are
then AES-GCM-encrypted to `{public_key}` (fresh ephemeral ECDH keypair per encryption, shared secret via
ECDH &#43; HKDF-SHA256, output `ephemeral_public_key.iv.ciphertext`, each part base64url) and the browser is
redirected to `https://{requesting_host}/auth/from/{ciphertext}?start_path={start_path}`.

##### `/auth/from/{encrypted_account_auth_tokens}`: receiving side
`Pages.Auth.From.EncryptedAccountAuthTokens_`, closing the loop from
[`/auth/to`](#authtopublic_keyrequesting_host-sending-side) above. Reached only via that redirect.
* **Path params**: `{encrypted_account_auth_tokens}` is the `ephemeral_public_key.iv.ciphertext` blob produced by
[`/auth/to`](#authtopublic_keyrequesting_host-sending-side).
* **Query params**: `start_path`, passed through unchanged from
[`/auth/to`](#authtopublic_keyrequesting_host-sending-side); defaults to `/` if missing.
* **Behavior**: decrypts `{encrypted_account_auth_tokens}` using the private key this origin generated when it
built the [`/auth/to`](#authtopublic_keyrequesting_host-sending-side) link (same ECDH &#43; HKDF-SHA256 &#43; AES-GCM
derivation, in reverse), yielding `bullcity.social`&#39;s hostname and its `refresh_token`/`access_token`. Calls
[`GetCurrentUser`](#grpc-api-GetCurrentUser) against that server with the decrypted `access_token` to hydrate the
rest of the account, then adds it straight to the local Accounts panel and navigates to `start_path` - no
confirmation step (decryption succeeding is itself the authenticity check: the ciphertext is AEAD-encrypted to
this origin&#39;s own one-time private key, so a forged or replayed payload just fails to decrypt rather than
producing a wrong-but-valid account). If either step fails (bad decrypt, or the `GetCurrentUser` call itself),
an error is shown instead. Either way, once the flow completes (added, or failed), the one-time private key is
discarded and a fresh keypair generated, so it&#39;s single-use per completed/failed transfer.

### gRPC API

| Method Name | Request Type | Response Type | Description |
| ----------- | ------------ | ------------- | ------------|
| GetServiceVersion | [.google.protobuf.Empty](#google-protobuf-Empty) | [GetServiceVersionResponse](#rellm-GetServiceVersionResponse) | Get the version (from Cargo) of the Rellm service. *Publicly accessible.* |
| GetServerConfiguration | [.google.protobuf.Empty](#google-protobuf-Empty) | [ServerConfiguration](#rellm-ServerConfiguration) | Gets the Rellm server&#39;s configuration. *Publicly accessible.* |
| CreateAccount | [CreateAccountRequest](#rellm-CreateAccountRequest) | [RefreshTokenResponse](#rellm-RefreshTokenResponse) | Creates a user account and provides a `refresh_token` (along with an `access_token`). *Publicly accessible.* |
| Login | [LoginRequest](#rellm-LoginRequest) | [RefreshTokenResponse](#rellm-RefreshTokenResponse) | Logs in a user and provides a `refresh_token` (along with an `access_token`). *Publicly accessible.* |
| AccessToken | [AccessTokenRequest](#rellm-AccessTokenRequest) | [AccessTokenResponse](#rellm-AccessTokenResponse) | Gets a new `access_token` (and possibly a new `refresh_token`, which should replace the old one in client storage), given a `refresh_token`. *Publicly accessible.* |
| GetCurrentUser | [.google.protobuf.Empty](#google-protobuf-Empty) | [User](#rellm-User) | Gets the current user. *Authenticated.* |
| ResetPassword | [ResetPasswordRequest](#rellm-ResetPasswordRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Resets the current user&#39;s - or, for admins, a given user&#39;s - password. *Authenticated.* |
| GetMedia | [GetMediaRequest](#rellm-GetMediaRequest) | [GetMediaResponse](#rellm-GetMediaResponse) | Gets Media (Images, Videos, etc) uploaded/owned by the current user. *Authenticated.* To upload/download actual Media blob/binary data, use the [HTTP Media APIs](#media). |
| DeleteMedia | [Media](#rellm-Media) | [.google.protobuf.Empty](#google-protobuf-Empty) | Deletes a media item by ID. *Authenticated.* Note that media may still be accessible for 12 hours after deletes are requested, as separate jobs clean it up from S3/MinIO. Deleting other users&#39; media requires `ADMIN` permissions. |
| UpdateMedia | [Media](#rellm-Media) | [Media](#rellm-Media) | Updates a Media item&#39;s `name`/`description`/`metadata.video_preview_time_ms` by ID. *Authenticated.* Every other field (visibility, moderation, `sizes`, etc.) is ignored -- use other RPCs (or, for `sizes`, `DeleteMediaSizes`) to change them. If `metadata` is set and its `video_preview_time_ms` differs from the item&#39;s current value, any existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes are deleted (both from `sizes` and their backing MinIO objects) so `convert_media_sizes` regenerates them at the new time -- see `MediaMetadata` and `MediaConversion`&#39;s own docs. Updating other users&#39; media requires `ADMIN` permissions. |
| DeleteMediaSizes | [Media](#rellm-Media) | [Media](#rellm-Media) | Deletes only the given `sizes` (matched by `conversion`) of a Media item by ID, e.g. to reclaim space by dropping `MEDIA_CONVERSION_ORIGINAL` once converted copies exist to serve in its place. *Authenticated.* Deleting other users&#39; media requires `ADMIN` permissions. Errors if this would leave the Media item with no `sizes` at all -- use `DeleteMedia` to remove the whole item instead. |
| GetUsers | [GetUsersRequest](#rellm-GetUsersRequest) | [GetUsersResponse](#rellm-GetUsersResponse) | Gets Users. *Publicly accessible **or** Authenticated.* Unauthenticated calls only return Users of `GLOBAL_PUBLIC` visibility. |
| UpdateUser | [User](#rellm-User) | [User](#rellm-User) | Update a user by ID. *Authenticated.* Updating other users requires `ADMIN` permissions. |
| StartContactMethodVerification | [ContactMethod](#rellm-ContactMethod) | [ContactMethod](#rellm-ContactMethod) | Starts SMS verification of the current user&#39;s own phone ContactMethod. *Authenticated, self-only.* Requires the server to have Twilio configured and enabled. Generates a 6-digit code, sends it via Twilio SMS, and stores it (with a start time and attempt counter) on the phone ContactMethod. Only `tel:` values are supported this iteration -- `mailto:` returns `Unimplemented`. Rate-limited to one send per 60 seconds per user. |
| VerifyContactMethod | [VerifyContactMethodRequest](#rellm-VerifyContactMethodRequest) | [ContactMethod](#rellm-ContactMethod) | Verifies a code sent by [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification). *Authenticated, self-only.* On match, sets `verified_at` and clears `verification_in_progress`. Codes expire after 10 minutes and allow at most 5 attempts before requiring a fresh [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification) call. |
| DeleteUser | [User](#rellm-User) | [.google.protobuf.Empty](#google-protobuf-Empty) | Deletes a user by ID. *Authenticated.* Deleting other users requires `ADMIN` permissions. |
| SendMessage | [SendMessageRequest](#rellm-SendMessageRequest) | [Message](#rellm-Message) | Sends a Message to one or more recipients (creating/reusing their MessagingGroup). *Publicly accessible **or** Authenticated.* Like [`CreatePost`](#grpc-api-CreatePost)/[`CreateEvent`](#grpc-api-CreateEvent), authentication (if any) is via a standard `access_token`; unauthenticated calls are simply sent with no `sender`. |
| GetMessages | [GetMessagesRequest](#rellm-GetMessagesRequest) | [GetMessagesResponse](#rellm-GetMessagesResponse) | Gets Messages. *Authenticated.* `PERSONAL_MESSAGES(_TEXT_SEARCH)` (and looking up a single Message/MessagingGroup) requires the `READ_PERSONAL_MESSAGES` permission and only returns Messages the current user sent or received. `ALL_SYSTEM_MESSAGES(_TEXT_SEARCH)` requires the `READ_ALL_SYSTEM_MESSAGES` permission and returns every Message on the server. |
| MarkMessagesRead | [MarkMessagesReadRequest](#rellm-MarkMessagesReadRequest) | [MarkMessagesReadResponse](#rellm-MarkMessagesReadResponse) | Marks one or more Messages as read (or unread) by the current user, e.g. every message in a thread once it&#39;s been opened. *Authenticated.* Only needs the recipient/sender access [`GetMessages`](#grpc-api-GetMessages) already requires for each Message - no separate permission. Atomic: if the caller lacks access to *any* of `message_ids`, none of them are marked (matching `MarkMessagesReadRequest.message_ids`&#39; own doc), so a client never has to reconcile a partially-applied batch. |
| RegisterPushSubscription | [RegisterPushSubscriptionRequest](#rellm-RegisterPushSubscriptionRequest) | [PushSubscription](#rellm-PushSubscription) | Registers (or re-registers) a browser&#39;s Web Push subscription for the current user, so new Messages sent/delivered to them (in-app or via email) push a notification to it even while the browser tab is closed. *Authenticated.* Re-registering an already-registered `endpoint` (e.g. because `PushManager.subscribe()` refreshed its keys) updates it in place rather than erroring. No-ops (server-side; not surfaced as an error to the caller) if the server has no [`WebPushConfig`](#rellm-WebPushConfig) configured - there&#39;s nothing to push notifications *with*. |
| UnregisterPushSubscription | [UnregisterPushSubscriptionRequest](#rellm-UnregisterPushSubscriptionRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Unregisters a browser&#39;s Web Push subscription, e.g. on logout or when `PushManager.subscribe()` reports the subscription as no longer valid. *Authenticated.* Not an error if `endpoint` isn&#39;t currently registered to the calling user. |
| GetPushSubscriptionStatus | [GetPushSubscriptionStatusRequest](#rellm-GetPushSubscriptionStatusRequest) | [GetPushSubscriptionStatusResponse](#rellm-GetPushSubscriptionStatusResponse) | Checks whether the calling user specifically (not just &#34;some account on this browser&#34;) has a [`PushSubscription`](#rellm-PushSubscription) registered for `endpoint`. *Authenticated.* Exists because a browser only ever exposes its own subscription&#39;s `endpoint`/keys, never *who* on the server side is registered against it - multiple local accounts on the same server can share one browser subscription (see [`RegisterPushSubscription`](#grpc-api-RegisterPushSubscription)&#39;s own doc comment), so knowing the endpoint alone isn&#39;t enough to know which of them are actually notified by it. |
| CreateFollow | [Follow](#rellm-Follow) | [Follow](#rellm-Follow) | Follow (or request to follow) a user. *Authenticated.* |
| UpdateFollow | [Follow](#rellm-Follow) | [Follow](#rellm-Follow) | Used to approve follow requests. *Authenticated.* |
| DeleteFollow | [Follow](#rellm-Follow) | [.google.protobuf.Empty](#google-protobuf-Empty) | Unfollow (or unrequest) a user. *Authenticated.* |
| GetGroups | [GetGroupsRequest](#rellm-GetGroupsRequest) | [GetGroupsResponse](#rellm-GetGroupsResponse) | Gets Groups. *Publicly accessible **or** Authenticated.* Unauthenticated calls only return Groups of `GLOBAL_PUBLIC` visibility. |
| CreateGroup | [Group](#rellm-Group) | [Group](#rellm-Group) | Creates a group with the current user as its admin. *Authenticated.* Requires the `CREATE_GROUPS` permission. |
| UpdateGroup | [Group](#rellm-Group) | [Group](#rellm-Group) | Update a Groups&#39;s information, default membership permissions or moderation. *Authenticated.* Requires `ADMIN` permissions within the group, or `ADMIN` permissions for the user. |
| DeleteGroup | [Group](#rellm-Group) | [.google.protobuf.Empty](#google-protobuf-Empty) | Delete a Group. *Authenticated.* Requires `ADMIN` permissions within the group, or `ADMIN` permissions for the user. |
| GetMembers | [GetMembersRequest](#rellm-GetMembersRequest) | [GetMembersResponse](#rellm-GetMembersResponse) | Get Members (User&#43;Membership) of a Group. *Publicly accessible **or** Authenticated.* |
| CreateMembership | [Membership](#rellm-Membership) | [Membership](#rellm-Membership) | Requests to join a group (or joins it), or sends an invite to the user. *Authenticated.* Memberships and moderations are set to their defaults. |
| UpdateMembership | [Membership](#rellm-Membership) | [Membership](#rellm-Membership) | Update aspects of a user&#39;s membership. *Authenticated.* Updating permissions requires `ADMIN` permissions within the group, or `ADMIN` permissions for the user. Updating moderation (approving/denying/banning) requires the same, or `MODERATE_USERS` permissions within the group. |
| DeleteMembership | [Membership](#rellm-Membership) | [.google.protobuf.Empty](#google-protobuf-Empty) | Leave a group (or cancel membership request). *Authenticated.* |
| GetPosts | [GetPostsRequest](#rellm-GetPostsRequest) | [GetPostsResponse](#rellm-GetPostsResponse) | Gets Posts. *Publicly accessible **or** Authenticated.* Unauthenticated calls only return Posts of `GLOBAL_PUBLIC` visibility. |
| CreatePost | [Post](#rellm-Post) | [Post](#rellm-Post) | Creates a Post. *Authenticated.* |
| UpdatePost | [Post](#rellm-Post) | [Post](#rellm-Post) | Updates a Post. *Authenticated.* |
| DeletePost | [Post](#rellm-Post) | [Post](#rellm-Post) | (TODO) (Soft) deletes a Post. Returns the deleted version of the Post. *Authenticated.* |
| StarPost | [Post](#rellm-Post) | [Post](#rellm-Post) | Star a Post. *Unauthenticated.* |
| UnstarPost | [Post](#rellm-Post) | [Post](#rellm-Post) | Unstar a Post. *Unauthenticated.* |
| SyncPost | [SyncPostRequest](#rellm-SyncPostRequest) | [Post](#rellm-Post) | Syncs (cross-posts) a Post to a SyncDestination. *Authenticated* (destination owner, or Admin), requires `SYNC_POSTS_TO_FACEBOOK` (or Admin). |
| DeletePostSyncDestination | [DeletePostSyncDestinationRequest](#rellm-DeletePostSyncDestinationRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Removes a Post&#39;s sync (cross-post) to a SyncDestination, the reverse of [`SyncPost`](#grpc-api-SyncPost). *Authenticated* (destination owner, or Admin), requires `SYNC_POSTS_TO_FACEBOOK` (or Admin). |
| GetGroupPosts | [GetGroupPostsRequest](#rellm-GetGroupPostsRequest) | [GetGroupPostsResponse](#rellm-GetGroupPostsResponse) | Get GroupPosts for a Post (and optional group). *Publicly accessible **or** Authenticated.* |
| CreateGroupPost | [GroupPost](#rellm-GroupPost) | [GroupPost](#rellm-GroupPost) | Cross-post a Post to a Group. *Authenticated.* |
| UpdateGroupPost | [GroupPost](#rellm-GroupPost) | [GroupPost](#rellm-GroupPost) | Group Moderators: Approve/Reject a GroupPost. *Authenticated.* |
| DeleteGroupPost | [GroupPost](#rellm-GroupPost) | [.google.protobuf.Empty](#google-protobuf-Empty) | Delete a GroupPost. *Authenticated.* |
| GetEvents | [GetEventsRequest](#rellm-GetEventsRequest) | [GetEventsResponse](#rellm-GetEventsResponse) | Gets Events. *Publicly accessible **or** Authenticated.* Unauthenticated calls only return Events of `GLOBAL_PUBLIC` visibility. |
| CreateEvent | [Event](#rellm-Event) | [Event](#rellm-Event) | Creates an Event. *Authenticated.* |
| UpdateEvent | [Event](#rellm-Event) | [Event](#rellm-Event) | Updates an Event. Automatically creates/updates/deletes child Occasions of the Event. *Authenticated.* Since Events are more complex structures, [`UpdateEventDetails`](#grpc-api-UpdateEventDetails), [`CreateNewOccasions`](#grpc-api-CreateNewOccasions), [`UpdateOccasions`](#grpc-api-UpdateOccasions), and [`DeleteRemovedOccasions`](#grpc-api-DeleteRemovedOccasions) are provided as separate RPCs to break down what happens during this request. |
| DeleteEvent | [Event](#rellm-Event) | [Event](#rellm-Event) | (Soft) deletes a Event. Returns the deleted version of the Event. *Authenticated.* |
| UpdateEventDetails | [Event](#rellm-Event) | [Event](#rellm-Event) | Updates only the [`Event`](#rellm-Event)&#39;s top-level details and those of its [`Post`](#rellm-Post) (not any [`Occasion`](#rellm-Occasion)s or their [`Post`](#rellm-Post)s). *Authenticated.* |
| CreateNewOccasions | [Event](#rellm-Event) | [Event](#rellm-Event) | Creates Occasions in an existing Event for every Occasion in the request that isn&#39;t already on the event. *Authenticated.* Any other Occasions in the request are ignored. |
| UpdateOccasions | [Event](#rellm-Event) | [Event](#rellm-Event) | Updates Occasions in an existing Event for every Occasion in the request that&#39;s already on the event. Any other Occasions in the request are ignored. *Authenticated.* |
| DeleteRemovedOccasions | [Event](#rellm-Event) | [Event](#rellm-Event) | Deletes Occasions in an existing Event that aren&#39;t present in the input Event. *Authenticated.* |
| GetSyncSources | [User](#rellm-User) | [GetSyncSourcesResponse](#rellm-GetSyncSourcesResponse) | Gets a user&#39;s SyncSources. *Authenticated* (self, or Admin for any user). |
| CreateSyncSource | [SyncSource](#rellm-SyncSource) | [SyncSource](#rellm-SyncSource) | Creates a SyncSource for the current user. *Authenticated*, requires `SYNC_EVENTS_FROM_ICS`/ `SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM` (whichever matches `configuration`, or Admin). |
| UpdateSyncSource | [SyncSource](#rellm-SyncSource) | [SyncSource](#rellm-SyncSource) | Updates a SyncSource. *Authenticated* (owner, or Admin for any user&#39;s), requires `SYNC_EVENTS_FROM_ICS`/`SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM` (whichever matches the effective `configuration` - the request&#39;s own if set, else the existing source&#39;s - or Admin). |
| DeleteSyncSource | [DeleteSyncSourceRequest](#rellm-DeleteSyncSourceRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Deletes a SyncSource. *Authenticated* (owner, or Admin). |
| GetSyncDestinations | [User](#rellm-User) | [GetSyncDestinationsResponse](#rellm-GetSyncDestinationsResponse) | Gets a user&#39;s SyncDestinations. *Authenticated* (self, or Admin for any user). |
| CreateSyncDestination | [SyncDestination](#rellm-SyncDestination) | [SyncDestination](#rellm-SyncDestination) | Creates a SyncDestination for the current user. *Authenticated*, requires `SYNC_EVENTS_TO_FACEBOOK` or `SYNC_POSTS_TO_FACEBOOK` (or Admin). |
| UpdateSyncDestination | [SyncDestination](#rellm-SyncDestination) | [SyncDestination](#rellm-SyncDestination) | Updates a SyncDestination. *Authenticated* (owner, or Admin for any user&#39;s), requires `SYNC_EVENTS_TO_FACEBOOK` or `SYNC_POSTS_TO_FACEBOOK` (or Admin). |
| DeleteSyncDestination | [DeleteSyncDestinationRequest](#rellm-DeleteSyncDestinationRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Deletes a SyncDestination. *Authenticated* (owner, or Admin). |
| SyncOccasion | [SyncOccasionRequest](#rellm-SyncOccasionRequest) | [Occasion](#rellm-Occasion) | Syncs (cross-posts) an Occasion to a SyncDestination. *Authenticated* (destination owner, or Admin), requires `SYNC_EVENTS_TO_FACEBOOK` (or Admin). |
| DeleteOccasionSyncDestination | [DeleteOccasionSyncDestinationRequest](#rellm-DeleteOccasionSyncDestinationRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Removes an Occasion&#39;s sync (cross-post) to a SyncDestination, the reverse of [`SyncOccasion`](#grpc-api-SyncOccasion). *Authenticated* (destination owner, or Admin), requires `SYNC_EVENTS_TO_FACEBOOK` (or Admin). |
| GetAIProviders | [User](#rellm-User) | [GetAIProvidersResponse](#rellm-GetAIProvidersResponse) | Gets a user&#39;s AIProviders. *Authenticated* (self, or Admin for any user). |
| CreateAIProvider | [AIProvider](#rellm-AIProvider) | [AIProvider](#rellm-AIProvider) | Creates an AIProvider for the current user. *Authenticated*, requires `CREATE_AI_PROVIDERS` (or Admin). |
| UpdateAIProvider | [AIProvider](#rellm-AIProvider) | [AIProvider](#rellm-AIProvider) | Updates an AIProvider&#39;s name, provider, or credentials. *Authenticated* (owner, or Admin for any user&#39;s). |
| DeleteAIProvider | [DeleteAIProviderRequest](#rellm-DeleteAIProviderRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Deletes an AIProvider (and its AIProviderGrants). *Authenticated* (owner, or Admin). |
| GrantAIProvider | [GrantAIProviderRequest](#rellm-GrantAIProviderRequest) | [AIProviderGrant](#rellm-AIProviderGrant) | Grants (or resets) another user&#39;s metered access to one of the current user&#39;s AIProviders. *Authenticated*, owner-only (no Admin override). |
| RevokeAIProvider | [RevokeAIProviderRequest](#rellm-RevokeAIProviderRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Revokes another user&#39;s access to one of the current user&#39;s AIProviders. *Authenticated*, owner-only (no Admin override). |
| GetMarketProducts | [GetMarketProductsRequest](#rellm-GetMarketProductsRequest) | [GetMarketProductsResponse](#rellm-GetMarketProductsResponse) | Gets MarketProducts available for purchase on this server (`market.proto`). *Unauthenticated* -- admins additionally see delisted MarketProducts. |
| CreateMarketProduct | [MarketProduct](#rellm-MarketProduct) | [MarketProduct](#rellm-MarketProduct) | Creates a MarketProduct. *Authenticated*, requires Admin. |
| UpdateMarketProduct | [MarketProduct](#rellm-MarketProduct) | [MarketProduct](#rellm-MarketProduct) | Updates a MarketProduct&#39;s amount/currency/details/delisted_at. *Authenticated*, requires Admin. `type`/`period` are immutable after creation and are ignored if changed. |
| GetMarketSubscriptions | [GetMarketSubscriptionsRequest](#rellm-GetMarketSubscriptionsRequest) | [GetMarketSubscriptionsResponse](#rellm-GetMarketSubscriptionsResponse) | Gets MarketSubscriptions -- self-scoped (&#34;MY subscriptions&#34;, `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE`, the default) for any authenticated caller, or every `PURCHASE_TYPE_RELLM_HOSTING` subscription across every buyer (`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`, backing `/market/fulfillment` -- see `RellmHostingSubscriptionDetails.fulfillment_status`&#39;s own doc) for an Admin. *Authenticated*. |
| MakeMarketPurchase | [MakeMarketPurchaseRequest](#rellm-MakeMarketPurchaseRequest) | [MakeMarketPurchaseResponse](#rellm-MakeMarketPurchaseResponse) | Starts (or resumes) buying a MarketProduct for the current user, returning a Stripe Checkout URL to redirect to. *Authenticated*. See `MakeMarketPurchaseRequest`&#39;s own doc -- no MarketPurchase/ MarketSubscription is created by this call itself, only once Stripe confirms payment via webhook. |
| CancelMarketSubscription | [MarketSubscription](#rellm-MarketSubscription) | [MarketSubscription](#rellm-MarketSubscription) | Cancels a MarketSubscription by setting `canceled_at` to now -- entitlement (media storage quota, granted permissions, etc.) stays active until whichever is later of `renews_at`/`canceled_at`; the `renew_market_subscriptions` background job is what actually revokes it and sets `service_terminated_at`, once both have passed. *Authenticated* -- the subscription&#39;s own buyer, or an Admin. |
| UpdateMarketSubscription | [MarketSubscription](#rellm-MarketSubscription) | [MarketSubscription](#rellm-MarketSubscription) | Appends to a `PURCHASE_TYPE_RELLM_HOSTING` MarketSubscription&#39;s own `fulfillment_notes` (nothing else -- every other field, including `additional_information`, is immutable after purchase and silently ignored if changed) -- backs `/market/fulfillment`. A new entry must be appended (not inserted/reordered/removed) after whatever&#39;s already stored, and its `user_id` must match the caller&#39;s own -- the server stamps `created_at` itself, ignoring whatever the client sent. Its `note` text is required unless the entry also changes `fulfillment_status` from the previous entry&#39;s own value (see `FulfillmentNote.note`&#39;s own doc). `fulfillment_status` on the returned `RellmHostingSubscriptionDetails` is always the last appended entry&#39;s own value -- there&#39;s no way to set it independently of a note. *Authenticated*, requires Admin (for now -- see that field&#39;s own doc on why this may loosen to &#34;buyer, or Admin&#34; later). |
| GenerateMedia | [GenerateMediaRequest](#rellm-GenerateMediaRequest) | [Media](#rellm-Media) | Generates (or edits, given reference `media_ids`) an image via one of the current user&#39;s AIModels, storing it as a new Media and, if `target` is set, attaching it to that Post/Event. *Authenticated* - caller must own or have been granted access to the chosen AIProvider, and (if `target` is set) have edit access to that Post/Event. A grantee (never the provider&#39;s own owner) spends real AIProviderGrant.tokens_remaining on every call - the provider&#39;s own reported token usage once generation succeeds, or (rejected before any request is even sent to the provider) a rough pre-flight estimate of the request&#39;s input cost alone, whichever catches an insufficient balance first. |
| GetEventAttendances | [GetEventAttendancesRequest](#rellm-GetEventAttendancesRequest) | [EventAttendances](#rellm-EventAttendances) | Gets EventAttendances for an Occasion. *Publicly accessible **or** Authenticated.* |
| UpsertEventAttendance | [EventAttendance](#rellm-EventAttendance) | [EventAttendance](#rellm-EventAttendance) | Upsert an EventAttendance. *Publicly accessible **or** Authenticated, with anonymous RSVP support.* See [EventAttendance](#rellm-EventAttendance) and [AnonymousAttendee](#rellm-AnonymousAttendee) for details. tl;dr: Anonymous RSVPs may updated/deleted with the `AnonymousAttendee.auth_token` returned by this RPC (the client should save this for the user, and ideally, offer a link with the token). |
| DeleteEventAttendance | [EventAttendance](#rellm-EventAttendance) | [.google.protobuf.Empty](#google-protobuf-Empty) | Delete an EventAttendance. *Publicly accessible **or** Authenticated, with anonymous RSVP support.* |
| FederateProfile | [FederatedAccount](#rellm-FederatedAccount) | [FederatedAccount](#rellm-FederatedAccount) | Federate the current user&#39;s profile with another user profile. *Authenticated*. |
| DefederateProfile | [FederatedAccount](#rellm-FederatedAccount) | [.google.protobuf.Empty](#google-protobuf-Empty) | Authenticated*. |
| ConfigureServer | [ServerConfiguration](#rellm-ServerConfiguration) | [ServerConfiguration](#rellm-ServerConfiguration) | Configure the server (i.e. the response to GetServerConfiguration). *Authenticated.* Requires `ADMIN` permissions. Editing `cluster_resources` additionally requires `EDIT_CLUSTER_SETTINGS` - see that field&#39;s own doc. |
| LockClusterResources | [LockClusterResourcesRequest](#rellm-LockClusterResourcesRequest) | [LockClusterResourcesResponse](#rellm-LockClusterResourcesResponse) | Attempts to acquire one or more `ClusterResource` locks on behalf of `namespace_id`. *Not part of the authenticated-user auth system* - this is server-to-server, cluster-internal coordination, authorized *entirely* by the `cluster-shared-secret` gRPC metadata header matching this server&#39;s own stored [`ClusterResources.cluster_shared_secret`](#rellm-ClusterResources) - knowing the secret is what makes a caller entitled to treat this server as the conductor, regardless of what this server&#39;s own `ClusterResources.namespace_id`/`conductor_host` happen to say. Fails with `FAILED_PRECONDITION` if this server has no `cluster_resources` configured at all (nothing to check the secret against), and with `UNAUTHENTICATED` if the header is missing or doesn&#39;t match. See [`LockClusterResourcesResponse`](#rellm-LockClusterResourcesResponse) for the polling contract this expects of callers. |
| FreeClusterResources | [FreeClusterResourcesRequest](#rellm-FreeClusterResourcesRequest) | [.google.protobuf.Empty](#google-protobuf-Empty) | Releases resources previously acquired via [`LockClusterResources`](#grpc-api-LockClusterResources). *Publicly accessible **or** Authenticated* - unlike `LockClusterResources`, this accepts *either* the `cluster-shared-secret` header (same as `LockClusterResources`) *or* normal per-user auth, in which case the caller needs `EDIT_CLUSTER_SETTINGS` (see that permission&#39;s own doc) and the header is ignored entirely - this is what lets an admin free a stuck lock straight from the Cluster tab UI rather than needing shell access to the cluster&#39;s shared secret. See [`FreeClusterResourcesRequest`](#rellm-FreeClusterResourcesRequest)&#39;s own doc for its no-op-if-not-held behavior. |
| ResetData | [.google.protobuf.Empty](#google-protobuf-Empty) | [.google.protobuf.Empty](#google-protobuf-Empty) | Delete ALL Media, Posts, Groups and Users except the user who performed the RPC. *Authenticated.* Requires `ADMIN` permissions. Note: Server Configuration is not deleted. |
| StreamReplies | [Post](#rellm-Post) | [Post](#rellm-Post) stream | (TODO) Reply streaming interface. Currently just streams fake example data. |

 



<a name="authentication-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## authentication.proto



<a name="rellm-AccessTokenRequest"></a>

### AccessTokenRequest
Request for a new access token using a refresh token.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| refresh_token | [string](#string) |  | The refresh token to use to request a new access token. |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Optional *requested* expiration time for the token. Server may ignore this. |






<a name="rellm-AccessTokenResponse"></a>

### AccessTokenResponse
Returned when requesting access tokens.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| refresh_token | [ExpirableToken](#rellm-ExpirableToken) | optional | If a refresh token is returned, it should be stored. Old refresh tokens may expire *before* their indicated expiration. See: https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation |
| access_token | [ExpirableToken](#rellm-ExpirableToken) |  | The new access token. |






<a name="rellm-CreateAccountRequest"></a>

### CreateAccountRequest
Request to create a new account.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| username | [string](#string) |  | Username for the account to be created. Must not exist. |
| password | [string](#string) |  | Password for the account to be created. Must be at least 8 characters. |
| email | [ContactMethod](#rellm-ContactMethod) | optional | Email to be used as a contact method. |
| phone | [ContactMethod](#rellm-ContactMethod) | optional | Phone number to be used as a contact method. |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Request an expiration time for the Auth Token returned. By default it will not expire. |
| device_name | [string](#string) | optional | (Not yet implemented.) The name of the device being used to create the account. |






<a name="rellm-CreateThirdPartyRefreshTokenRequest"></a>

### CreateThirdPartyRefreshTokenRequest
Request to create a new third-party refresh token. Unlike [`LoginRequest`](#rellm-LoginRequest) or [`CreateAccountRequest`](#rellm-CreateAccountRequest), the user must be logged in to create a third-party refresh token.

Generally, this is used to create a refresh token for another Rellm instance,
e.g., accessing `bullcity.social/jon`&#39;s data from `jonline.io`. On the web side, this is implemented as follows:

1. When the `bullcity.social` user wants to login on `jonline.io`, `bullcity.social` will redirect 
the user to `jonline.io/third_party_auth?to=bullcity.social`.
2. `jonline.io` will force the user to login if needed on this page.
3. `jonline.io` will prompt/warn the user, and then call this RPC to create a refresh &#43; access token for `bullcity.social`.
4. `jonline.io` will redirect the user back to `bullcity.social/third_party_auth?from=jonline.io&amp;token=&lt;Base64RefreshTokenResponse&gt;` with the refresh token POSTed in form data.
    * (`&lt;Base64RefreshTokenResponse&gt;` is a base64-encoded [`RefreshTokenResponse`](#rellm-RefreshTokenResponse) message.)
6. `bullcity.social` will ensure it can [`GetCurrentUser`](#grpc-api-GetCurrentUser) on `jonline.io` with its new auth token.
5. `bullcity.social` will replace the current location with `bullcity.social/third_party_auth?from=jonline.io`.
7. `bullcity.social` will use the access token to make requests to `jonline.io` (the same as with `bullcity.social`).

Note that refresh tokens


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The third-party refresh token&#39;s expiration time. |
| user_id | [string](#string) |  | The third-party refresh token&#39;s user ID. |
| device_name | [string](#string) |  | The third-party refresh token&#39;s device name. |






<a name="rellm-ExpirableToken"></a>

### ExpirableToken
Generic type for refresh and access tokens.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| token | [string](#string) |  | The secure token value. |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Optional expiration time for the token. If not set, the token will not expire. |






<a name="rellm-LoginRequest"></a>

### LoginRequest
Request to login to an existing account.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| username | [string](#string) |  | Username for the account to be logged into. Must exist. |
| password | [string](#string) |  | Password for the account to be logged into. |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Request an expiration time for the Auth Token returned. By default it will not expire. |
| device_name | [string](#string) | optional | (Not yet implemented.) The name of the device being used to login. |
| user_id | [string](#string) | optional | (TODO) If provided, username is ignored and login is initiated via user_id instead. |






<a name="rellm-RefreshTokenMetadata"></a>

### RefreshTokenMetadata
Metadata on a refresh token for the current user, used when managing refresh tokens as a user.
Does not include the token itself.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [uint64](#uint64) |  | The DB ID of the refresh token. Used when deleting the token or updating the device_name. |
| expires_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Expiration date of the refresh token. |
| device_name | [string](#string) | optional | The device name the refresh token is on. User-updateable. |
| is_this_device | [bool](#bool) |  | Whether the refresh token is associated with the current device (based on what user is making the request). |
| third_party | [bool](#bool) |  |  |






<a name="rellm-RefreshTokenResponse"></a>

### RefreshTokenResponse
Returned when creating an account, logging in, or creating a third-party refresh token.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| refresh_token | [ExpirableToken](#rellm-ExpirableToken) |  | The persisted token the device should store and associate with the account. Used to request new access tokens. |
| access_token | [ExpirableToken](#rellm-ExpirableToken) |  | An initial access token provided for convenience. |
| user | [User](#rellm-User) |  | The user associated with the account that was created/logged into. |






<a name="rellm-ResetPasswordRequest"></a>

### ResetPasswordRequest
Request to reset a password.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) | optional | If not set, use the current user of the request. |
| password | [string](#string) |  | The new password to set. |






<a name="rellm-UserRefreshTokensResponse"></a>

### UserRefreshTokensResponse
Response for `GetUserRefreshTokens` RPC. Returns all refresh tokens associated with the current user.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| refresh_tokens | [RefreshTokenMetadata](#rellm-RefreshTokenMetadata) | repeated | The refresh tokens associated with the current user. |





 

 

 

 



<a name="visibility_moderation-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## visibility_moderation.proto


 


<a name="rellm-Moderation"></a>

### Moderation
Nearly everything in Rellm has one or more `Moderation`s on it.

From a high level:

- A [`User`](#rellm-User) has a `moderation` that determines whether they can log in (and their visibility per their `visibility`).
  (This is poorly enforced currently! Fix it if you want!)
    - This is managed by `people_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
      A default of `UNMODERATED` means that all users can log in. A default of `PENDING`
      means that all users must be approved by a moderator/admin before they can log in.
- A [`Follow`](#rellm-Follow) has a `target_user_moderation` that determines whether the [`User`](#rellm-User) is following the [`Group`](#rellm-Group).
   - It is managed by `default_follow_moderation` in the targeted [`User`](#rellm-User).
- A [`Group`](#rellm-Group) has a `moderation` that determines whether the [`Group`](#rellm-Group) is visible to users (per its `visibility`).
    - This is managed by `group_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
- A [`Membership`](#rellm-Membership) has a `group_moderation` and `user_moderation` that determine whether
  the [`Group`](#rellm-Group) admins and/or the invited user has approved the [`Membership`](#rellm-Membership), respectively.
    - User invites to [`Group`](#rellm-Group)s (i.e. the `user_moderation`) always start as `PENDING`.
      The group side of this is managed by `default_membership_moderation` of the [`Group`](#rellm-Group) in question.
- A [`Post`](#rellm-Post) has a `moderation` that determines whether the [`Post`](#rellm-Post) is visible to users (per its `visibility`).
    - This is managed by `post_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
- A [`GroupPost`](#rellm-GroupPost) has a `moderation` that determines whether the admins/mods of the [`Group`](#rellm-Group) has approved the [`Post`](#rellm-Post) (or [`Post`](#rellm-Post)-descended thing like [`Event`](#rellm-Event)s).
- [`Event`](#rellm-Event)s and further objects contain a [`Post`](#rellm-Post) and thus inherit its `moderation` and
  related [`GroupPost`](#rellm-GroupPost) behavior, for &#34;Group Events.&#34;

| Name | Number | Description |
| ---- | ------ | ----------- |
| MODERATION_UNKNOWN | 0 | A moderation that is not known to the protocol. (Likely, the client and server use different versions of the Rellm protocol.) |
| UNMODERATED | 1 | Subject has not been moderated and is visible to all users. |
| PENDING | 2 | Subject is awaiting moderation and not visible to any users. |
| APPROVED | 3 | Subject has been approved by moderators and is visible to all users. |
| REJECTED | 4 | Subject has been rejected by moderators and is not visible to any users. |



<a name="rellm-Visibility"></a>

### Visibility
Visibility in Rellm is a complex topic. There are several different types of visibility, 
and each type of entity ([`User`](#rellm-User), [`Media`](#rellm-Media), [`Group`](#rellm-Group), then [`Post`](#rellm-Post)/[`Event`](#rellm-Event)/etc. with common logic)
has different rules for visibility.

From the top down, the rules break down as follows:

- Even a `PRIVATE` entity is always visible to the user who owns it.
    - For [`Group`](#rellm-Group)s, this means all full members of the [`Group`](#rellm-Group).
    - For [`User`](#rellm-User)s, this is confusing and there is a whole [`PrivateUserStrategy`](#rellm-PrivateUserStrategy) thing
      in [`ServerConfiguration`](#rellm-ServerConfiguration) for this.
- A `LIMITED` entity is visible to to the owner(s) and any explicitly associated
  [`User`](#rellm-User)s and [`Group`](#rellm-Group)s. Generally, this only applies to [`Post`](#rellm-Post)/[`Event`](#rellm-Event)/etc. entities.
  Associations exist via [`UserPost`](#rellm-UserPost)s and [`GroupPost`](#rellm-GroupPost)s.
    - This is currently only implemented for [`Group`](#rellm-Group)s and [`GroupPost`](#rellm-GroupPost)s. There are some
      choices to be made about how to implement this for [`User`](#rellm-User)s and [`UserPost`](#rellm-UserPost)s, and whether
      `DIRECT` should be a separate visibility type.
- A `SERVER_PUBLIC` entity is visible to all authenticated users.
- A `GLOBAL_PUBLIC` entity is visible to the open internet.

| Name | Number | Description |
| ---- | ------ | ----------- |
| VISIBILITY_UNKNOWN | 0 | A visibility that is not known to the protocol. (Likely, the client and server use different versions of the Rellm protocol.) |
| PRIVATE | 1 | Subject is only visible to the user who owns it. |
| LIMITED | 2 | Subject is only visible to explictly associated Groups and Users. See: [`GroupPost`](#rellm-GroupPost) and [`UserPost`](#rellm-UserPost). |
| SERVER_PUBLIC | 3 | Subject is visible to all authenticated users. |
| GLOBAL_PUBLIC | 4 | Subject is visible to all users on the internet. |
| DIRECT | 5 | [TODO] Subject is visible to explicitly-associated Users. Only applicable to Posts and Events. For Users, this is the same as LIMITED. See: [`UserPost`](#rellm-UserPost). |


 

 

 



<a name="permissions-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## permissions.proto


 


<a name="rellm-Permission"></a>

### Permission
Rellm Permissions are a set of permissions that can be granted directly to [`User`](#rellm-User)s and [`Membership`](#rellm-Membership)s.
(A [`Membership`](#rellm-Membership) is the link between a [`Group`](#rellm-Group) and a [`User`](#rellm-User).)

Subsets of these permissions are also applicable to anonymous users via [`anonymous_user_permissions` in `ServerConfiguration`](#rellm-ServerConfiguration),
and to Group non-members via [`non_member_permissions` in `Group`](#rellm-Group), as well as others documented there.

| Name | Number | Description |
| ---- | ------ | ----------- |
| PERMISSION_UNKNOWN | 0 | A permission that could not be read using the Rellm protocol. (Perhaps, a permission from a newer Rellm version.) |
| VIEW_USERS | 1 | Allow the user to view profiles with `SERVER_PUBLIC` Visibility. Allow anonymous users to view profiles with `GLOBAL_PUBLIC` Visibility (when configured as an anonymous user permission). |
| PUBLISH_USERS_LOCALLY | 2 | Allow the user to publish profiles with `SERVER_PUBLIC` Visibility. This generally only applies to the user&#39;s own profile, except for Admins. |
| PUBLISH_USERS_GLOBALLY | 3 | Allow the user to publish profiles with `GLOBAL_PUBLIC` Visibility. This generally only applies to the user&#39;s own profile, except for Admins. |
| MODERATE_USERS | 4 | Allow the user to grant `VIEW_POSTS`, `CREATE_POSTS`, `VIEW_EVENTS` and `CREATE_EVENTS` permissions to users. |
| FOLLOW_USERS | 5 | Allow the user to follow other users. |
| GRANT_BASIC_PERMISSIONS | 6 | Allow the user to grant Basic Permissions to other users. &#34;Basic Permissions&#34; are defined by your [`ServerConfiguration`](#rellm-ServerConfiguration)&#39;s `basic_user_permissions`. |
| VIEW_GROUPS | 10 | Allow the user to view groups with `SERVER_PUBLIC` visibility. Allow anonymous users to view groups with `GLOBAL_PUBLIC` visibility (when configured as an anonymous user permission). |
| CREATE_GROUPS | 11 | Allow the user to create groups. |
| PUBLISH_GROUPS_LOCALLY | 12 | Allow the user to give groups `SERVER_PUBLIC` visibility. |
| PUBLISH_GROUPS_GLOBALLY | 13 | Allow the user to give groups `GLOBAL_PUBLIC` visibility. |
| MODERATE_GROUPS | 14 | The Moderate Groups permission makes a user effectively an admin of *any* group. |
| JOIN_GROUPS | 15 | Allow the user to (potentially request to) join groups of `SERVER_PUBLIC` or higher visibility. |
| INVITE_GROUP_MEMBERS | 16 | Allow the user to invite other users to groups. Only applicable as a Group permission (not at the User level). |
| VIEW_POSTS | 20 | As a user permission, allow the user to view posts with `SERVER_PUBLIC` or higher visibility. As a group permission, allow the user to view [`GroupPost`](#rellm-GroupPost)s whose [`Post`](#rellm-Post)s have `LIMITED` or higher visibility. Allow anonymous users to view posts with `GLOBAL_PUBLIC` visibility (when configured as an anonymous user permission). |
| CREATE_POSTS | 21 | As a user permission, allow the user to create [`Post`](#rellm-Post)s of `PRIVATE` and `LIMITED` visibility. As a group permission, allow the user to create [`GroupPost`](#rellm-GroupPost)s for `POST` and `FEDERATED_POST` [`PostContext`](#rellm-PostContext)s.. |
| PUBLISH_POSTS_LOCALLY | 22 | Allow the user to publish posts with `SERVER_PUBLIC` visibility. |
| PUBLISH_POSTS_GLOBALLY | 23 | Allow the user to publish posts with `GLOBAL_PUBLIC` visibility. |
| MODERATE_POSTS | 24 | Allow the user to moderate posts. |
| REPLY_TO_POSTS | 25 | Allow the user to reply to posts. |
| EDIT_POST_TITLES_AND_LINKS | 26 | Allow the user to edit post titles and/or links. |
| VIEW_EVENTS | 30 | As a user permission, allow the user to view posts with `SERVER_PUBLIC` or higher visibility. As a group permission, allow the user to view [`GroupPost`](#rellm-GroupPost)s whose [`Event`](#rellm-Event) [`Post`](#rellm-Post)s have `LIMITED` or higher visibility. Allow anonymous users to view events with `GLOBAL_PUBLIC` visibility (when configured as an anonymous user permission). |
| CREATE_EVENTS | 31 | As a user permission, allow the user to create [`Event`](#rellm-Event)s of `PRIVATE` and `LIMITED` visibility. As a group permission, allow the user to create [`GroupPost`](#rellm-GroupPost)s for `EVENT` and `FEDERATED_OCCASION` [`PostContext`](#rellm-PostContext)s.. |
| PUBLISH_EVENTS_LOCALLY | 32 | Allow the user to publish events with `SERVER_PUBLIC` visibility. |
| PUBLISH_EVENTS_GLOBALLY | 33 | Allow the user to publish events with `GLOBAL_PUBLIC` visibility. |
| MODERATE_EVENTS | 34 | Allow the user to moderate events. |
| RSVP_TO_EVENTS | 35 | Allow the user to RSVP to events that allow RSVPs. |
| VIEW_MEDIA | 40 | Allow the user to view media with `SERVER_PUBLIC` or higher visibility. *Not currently enforced.* Allow anonymous users to view media with `GLOBAL_PUBLIC` visibility (when configured as an anonymous user permission). *Not currently enforced.* |
| CREATE_MEDIA | 41 | Allow the user to create media of `PRIVATE` and `LIMITED` visibility. *Not currently enforced.* |
| PUBLISH_MEDIA_LOCALLY | 42 | Allow the user to publish media with `SERVER_PUBLIC` visibility. *Not currently enforced.* |
| PUBLISH_MEDIA_GLOBALLY | 43 | Allow the user to publish media with `GLOBAL_PUBLIC` visibility. *Not currently enforced.* |
| MODERATE_MEDIA | 44 | Allow the user to moderate events. |
| READ_PERSONAL_MESSAGES | 50 |  |
| READ_ALL_SYSTEM_MESSAGES | 51 |  |
| CREATE_AI_PROVIDERS | 60 | Allow the user to create/update their own [`AIProvider`](#rellm-AIProvider)s (see `ai_providers.proto`) and grant/revoke other users&#39; access to them. |
| SYNC_EVENTS_FROM_ICS | 700 | Allow the user to create/update [`SyncSource`](#rellm-SyncSource)s (iCal subscriptions) that synchronize [`Event`](#rellm-Event)s in. |
| SYNC_POSTS_FROM_RSS | 701 | Allow the user to create/update [`SyncSource`](#rellm-SyncSource)s (RSS subscriptions) that synchronize [`Post`](#rellm-Post)s in. |
| SYNC_POSTS_FROM_ATOM | 702 | Allow the user to create/update [`SyncSource`](#rellm-SyncSource)s (Atom subscriptions) that synchronize [`Post`](#rellm-Post)s in. |
| SYNC_EVENTS_TO_FACEBOOK | 1000 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected Facebook Page, and to sync Occasions to them. |
| SYNC_POSTS_TO_FACEBOOK | 1001 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected Facebook Page, and to sync Posts to them. |
| SYNC_EVENTS_TO_INSTAGRAM | 1010 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected Instagram Business/Creator account, and to sync Occasions to them. |
| SYNC_POSTS_TO_INSTAGRAM | 1011 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected Instagram Business/Creator account, and to sync Posts to them. |
| SYNC_EVENTS_TO_MASTODON | 1020 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected Mastodon account, and to sync Occasions to them. |
| SYNC_POSTS_TO_MASTODON | 1021 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected Mastodon account, and to sync Posts to them. |
| SYNC_EVENTS_TO_BLUESKY | 1030 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected Bluesky account, and to sync Occasions to them. |
| SYNC_POSTS_TO_BLUESKY | 1031 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected Bluesky account, and to sync Posts to them. |
| SYNC_EVENTS_TO_X_TWITTER | 1040 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected X (Twitter) account, and to sync Occasions to them. |
| SYNC_POSTS_TO_X_TWITTER | 1041 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected X (Twitter) account, and to sync Posts to them. |
| SYNC_EVENTS_TO_THREADS | 1050 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Occasions to a connected Threads account, and to sync Occasions to them. |
| SYNC_POSTS_TO_THREADS | 1051 | Allow the user to create/update [`SyncDestination`](#rellm-SyncDestination)s that cross-post Posts to a connected Threads account, and to sync Posts to them. |
| BUSINESS | 9998 | Indicates the user is a business. Used purely for display purposes. |
| RUN_BOTS | 9999 | Allow the user to run bots. There is no enforcement of this permission (yet), but it lets other users know that the user is allowed to run bots. |
| ADMIN | 10000 | Marks the user as an admin. In the context of user permissions, allows the user to configure the server, moderate/update visibility/permissions to any [`User`](#rellm-User), [`Group`](#rellm-Group), [`Post`](#rellm-Post) or [`Event`](#rellm-Event). In the context of group permissions, allows the user to configure the group, modify members and member permissions, and moderate [`GroupPost`](#rellm-GroupPost)s and `GroupEvent`s. |
| VIEW_PRIVATE_CONTACT_METHODS | 10001 | Allow the user to view the private contact methods of other users. Kept separate from `ADMIN` to allow for more fine-grained privacy control. |
| EDIT_CLUSTER_SETTINGS | 10002 | Allow the user to edit [`ServerConfiguration.cluster_resources`](#rellm-ClusterResources) via [`ConfigureServer`](#grpc-api-ConfigureServer). `cluster_resources` is otherwise visible (read-only) to any `ADMIN` - this permission gates *editing* it specifically, on top of `ADMIN`, since misconfiguring it (wrong `conductor_host`/`cluster_shared_secret`) affects cluster-mates this admin may not operate. Kept separate from `ADMIN` the same way `VIEW_PRIVATE_CONTACT_METHODS` is, and deliberately *not* grantable via [`UpdateUser`](#grpc-api-UpdateUser) like other permissions - only settable directly in the database (e.g. via the `set_permission` binary), so granting it is always a deliberate operator action, never a side effect of a normal admin-managing-admins flow. |


 

 

 



<a name="users-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## users.proto



<a name="rellm-ContactMethod"></a>

### ContactMethod
A contact method for a user. Verified via `StartContactMethodVerification`/`VerifyContactMethod`
-- SMS/Twilio only this iteration, see `TwilioConfig` in `server_configuration.proto`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| value | [string](#string) | optional | Either a valid `mailto:` or valid `tel:` URL. |
| visibility | [Visibility](#rellm-Visibility) |  | The visibility of the contact method. |
| supported_by_server | [bool](#bool) |  | Server-side flag indicating whether the server can verify (and otherwise interact via) the contact method. Always computed server-side (never trusted from client input) off whether a verification provider is currently enabled for this contact method&#39;s scheme (`tel:`/`mailto:`). |
| verified_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Time the contact method was verified. Indicates the user has completed verification of the contact method. Verification requires `supported_by_server` to be `true`. |
| verification_in_progress | [ContactMethodVerification](#rellm-ContactMethodVerification) | optional |  |






<a name="rellm-ContactMethodVerification"></a>

### ContactMethodVerification



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| verification_code | [string](#string) |  | Never serialized to gRPC by the backend. Only stored server-side; a client&#39;s own attempt to verify goes through `VerifyContactMethodRequest.code` instead, not this field. |
| verification_started_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| attempts | [int32](#int32) |  | Number of failed `VerifyContactMethod` attempts against `verification_code` since it was sent. Capped (see that RPC&#39;s own doc) to prevent brute-forcing the 6-digit code within its expiry window. |






<a name="rellm-Follow"></a>

### Follow
Model for a user&#39;s follow of another user.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The follower in the relationship. |
| target_user_id | [string](#string) |  | The user being followed. |
| target_user_moderation | [Moderation](#rellm-Moderation) |  | Tracks whether the target user needs to approve the follow. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the follow was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the follow was last updated. |






<a name="rellm-GetUsersRequest"></a>

### GetUsersRequest
Request to get one or more users by a variety of parameters.
Supported parameters depend on `listing_type`.

- `{listing_type: USERS_TEXT_SEARCH, search_text:}`
    - Full-text search across accessible users&#39; username, real name, and bio.
- `{listing_type: FOLLOWERS_TEXT_SEARCH, search_text:, user_id:}` (and the
  `FOLLOWING_TEXT_SEARCH`/`FRIENDS_TEXT_SEARCH`/`FOLLOW_REQUESTS_TEXT_SEARCH` equivalents)
    - Scopes that same full-text search to `user_id`&#39;s followers/following/friends/follow
      requests, same relationship rules as the non-search `listing_type`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| username | [string](#string) | optional | The username to search for. Substrings are supported. |
| user_id | [string](#string) | optional | The user ID to search for. |
| search_text | [string](#string) | optional | Full-text search query, matched against the user&#39;s username/real name/bio. Required (and only used) when `listing_type` is `USERS_TEXT_SEARCH` or one of the `*_TEXT_SEARCH` variants. |
| page | [int32](#int32) | optional | The page of results to return. Pages are 0-indexed. |
| listing_type | [UserListingType](#rellm-UserListingType) |  | The number of results to return per page. |






<a name="rellm-GetUsersResponse"></a>

### GetUsersResponse
Response to a [`GetUsersRequest`](#rellm-GetUsersRequest).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| users | [User](#rellm-User) | repeated | The users matching the request. |
| has_next_page | [bool](#bool) |  | Whether there are more pages of results. |






<a name="rellm-Membership"></a>

### Membership
Model for a user&#39;s membership in a group. Memberships are generically
included as part of User models when relevant in Rellm, but UIs should use the group_id
to reconcile memberships with groups.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The member (or requested/invited member). |
| group_id | [string](#string) |  | The group the membership pertains to. |
| permissions | [Permission](#rellm-Permission) | repeated | Valid Membership Permissions are: `VIEW_POSTS`, `CREATE_POSTS`, `MODERATE_POSTS`, `VIEW_EVENTS`, CREATE_EVENTS, `MODERATE_EVENTS`, `ADMIN`, `RUN_BOTS`, and `MODERATE_USERS` |
| group_moderation | [Moderation](#rellm-Moderation) |  | Tracks whether group moderators need to approve the membership. |
| user_moderation | [Moderation](#rellm-Moderation) |  | Tracks whether the user needs to approve the membership. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the membership was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the membership was last updated. |






<a name="rellm-User"></a>

### User
Model for a Rellm user. This user may have [`Media`](#rellm-Media), [`Group`](#rellm-Group) [`Membership`](#rellm-Membership)s,
[`Post`](#rellm-Post)s, [`Event`](#rellm-Event)s, and other objects associated with them.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Permanent string ID for the user. Will never contain a `@` symbol. |
| username | [string](#string) |  | Impermanent string username for the user. Will never contain a `@` symbol. |
| real_name | [string](#string) |  | The user&#39;s real name. |
| email | [ContactMethod](#rellm-ContactMethod) | optional | The user&#39;s email address. |
| phone | [ContactMethod](#rellm-ContactMethod) | optional | The user&#39;s phone number. |
| permissions | [Permission](#rellm-Permission) | repeated | The user&#39;s permissions. See [`Permission`](#rellm-Permission) for details. |
| avatar | [MediaReference](#rellm-MediaReference) | optional | The user&#39;s avatar. Note that its visibility is managed by the User and thus it may not be accessible to the current user. |
| bio | [string](#string) |  | The user&#39;s bio. |
| media_storage_limit_bytes | [uint64](#uint64) | optional | The maximum number of bytes this user&#39;s Media (see `Media.sizes[].size_bytes`) may collectively occupy in storage. Enforced by `POST /media` (see `Media`&#39;s own doc), which rejects an upload that would push `media_storage_bytes_used` over this limit with an HTTP 413 and a plaintext error body. Unset means unlimited. |
| media_storage_bytes_used | [uint64](#uint64) |  | The total size, in bytes, of every stored copy (original plus any converted sizes) of every Media item this user owns -- the sum of `Media.sizes[].size_bytes` across all their Media. A denormalized counter, recomputed (never trusted from client input) after every operation that could change it -- upload, delete, size conversion, `DeleteMediaSizes` -- by `backend/src/logic/user_counts.rs`&#39;s `update_media_storage_used`, and self-healed on an interval by `bin/update_user_counts.rs` the same way every other denormalized `User` counter (`follower_count`, `post_count`, etc.) is. |
| visibility | [Visibility](#rellm-Visibility) |  | User visibility is a bit different from Post visibility. LIMITED means the user can only be seen by users they follow (as opposed to Posts&#39; individualized visibilities). PRIVATE visibility means no one can see the user. See server_configuration.proto for details about PRIVATE users&#39; ability to creep. |
| moderation | [Moderation](#rellm-Moderation) |  | The user&#39;s moderation status. See [`Moderation`](#rellm-Moderation) for details. |
| default_follow_moderation | [Moderation](#rellm-Moderation) |  | Only PENDING or UNMODERATED are valid. |
| follower_count | [int32](#int32) | optional | The number of users following this user. |
| following_count | [int32](#int32) | optional | The number of users this user is following. |
| friend_count | [int32](#int32) | optional | The number of users this user mutually follows (and is followed by). |
| group_count | [int32](#int32) | optional | The number of groups this user is a member of. |
| post_count | [int32](#int32) | optional | The number of posts this user has made. |
| response_count | [int32](#int32) | optional | The number of responses to [`Post`](#rellm-Post)s and [`Event`](#rellm-Event)s this user has made. |
| event_count | [int32](#int32) | optional | The number of events this user has created. |
| occasion_count | [int32](#int32) | optional | The number of occasions this user has created (across all of their events). |
| current_user_follow | [Follow](#rellm-Follow) | optional | Presence indicates the current user is following or has a pending follow request for this user. |
| target_current_user_follow | [Follow](#rellm-Follow) | optional | Presence indicates this user is following or has a pending follow request for the current user. |
| current_group_membership | [Membership](#rellm-Membership) | optional | Returned by [`GetMembers`](#grpc-api-GetMembers) calls, for use when managing [`Group`](#rellm-Group) [`Membership`](#rellm-Membership)s. The [`Membership`](#rellm-Membership) should match the [`Group`](#rellm-Group) from the originating [`GetMembersRequest`](#rellm-GetMembersRequest), providing whether the user is a member of that [`Group`](#rellm-Group), has been invited, requested to join, etc.. |
| federated_profiles | [FederatedAccount](#rellm-FederatedAccount) | repeated | Federated profiles for the user. *Not always loaded.* This is a list of profiles from other servers that the user has connected to their account. Managed by the user via `Federate` |
| sync_destinations | [SyncDestination](#rellm-SyncDestination) | repeated | The target user&#39;s own linked SyncDestinations (e.g. Facebook Pages). Populated by [`GetUsers`](#grpc-api-GetUsers)&#39; single-user lookups (by username or by user_id) when the viewer is the target user themselves (and holds `SYNC_EVENTS_TO_FACEBOOK` or `SYNC_POSTS_TO_FACEBOOK`) or an Admin, and by [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser) (always a self-view) - always empty otherwise, including via every other [`GetUsers`](#grpc-api-GetUsers) listing type. |
| sync_sources | [SyncSource](#rellm-SyncSource) | repeated | The target user&#39;s own [`SyncSource`](#rellm-SyncSource)s. Unlike `sync_destinations`, also populated for the target user themselves *or an Admin* across every [`GetUsers`](#grpc-api-GetUsers) listing type (not just single-user lookups) - e.g. an Admin&#39;s `EVERYONE` listing gets every returned user&#39;s sources filled in, batch-loaded in one query rather than per-user. Also populated by [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser) (always a self-view). Always empty for any other viewer. |
| ai_models | [AIModel](#rellm-AIModel) | repeated | Every [`AIProvider`](#rellm-AIProvider) model the target user may currently call - their own providers&#39; models, plus any models granted to them on other users&#39; providers (see [`AIModel`](#rellm-AIModel)). Gated and populated the same way as `sync_sources` (target user themselves, or an Admin, across any [`GetUsers`](#grpc-api-GetUsers) listing type, plus [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser)). |
| market_subscriptions | [MarketSubscription](#rellm-MarketSubscription) | repeated | The target user&#39;s own MarketSubscriptions (`market.proto`), each with its own `billing_history`. Gated and populated the same way as `ai_models`/`sync_sources` (target user themselves, or an Admin, across any [`GetUsers`](#grpc-api-GetUsers) listing type, plus [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser)). |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the user was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the user was last updated. |






<a name="rellm-VerifyContactMethodRequest"></a>

### VerifyContactMethodRequest
Request for [`VerifyContactMethod`](#grpc-api-VerifyContactMethod).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| value | [string](#string) |  | The `tel:` (or, in the future, `mailto:`) value being verified -- must match the current user&#39;s own stored `phone`/`email` value. |
| code | [string](#string) |  | The code the user was sent by `StartContactMethodVerification`. |





 


<a name="rellm-UserListingType"></a>

### UserListingType
Ways of listing users.

| Name | Number | Description |
| ---- | ------ | ----------- |
| EVERYONE | 0 | Get all users. |
| FOLLOWING | 1 | Get users the current user is following. |
| FRIENDS | 2 | Get users who follow and are followed by the current user. |
| FOLLOWERS | 3 | Get users who follow the current user. |
| FOLLOW_REQUESTS | 4 | Get users who have requested to follow the current user. |
| USERS_TEXT_SEARCH | 5 | Returns users matching the full-text `search_text` query, scoped the same way `EVERYONE` is. Requires `search_text` parameter.

Named `USERS_TEXT_SEARCH` (not the bare `TEXT_SEARCH` used by [`PostListingType`](#rellm-PostListingType)) because proto3 enum values share a single namespace across the whole `rellm` package (C&#43;&#43; scoping rules) - [`PostListingType`](#rellm-PostListingType) already claimed `TEXT_SEARCH`. |
| FOLLOWERS_TEXT_SEARCH | 6 | Scopes `TEXT_SEARCH` to users following `user_id`. Requires `search_text` and `user_id`. |
| FOLLOWING_TEXT_SEARCH | 7 | Scopes `TEXT_SEARCH` to users `user_id` follows. Requires `search_text` and `user_id`. |
| FRIENDS_TEXT_SEARCH | 8 | Scopes `TEXT_SEARCH` to `user_id`&#39;s friends (mutual follows). Requires `search_text` and `user_id`. |
| FOLLOW_REQUESTS_TEXT_SEARCH | 9 | Scopes `TEXT_SEARCH` to the signed-in caller&#39;s pending follow requests. Requires `search_text`. |
| ADMINS | 10 | [TODO] Gets admins for a server. |


 

 

 



<a name="media-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## media.proto



<a name="rellm-Author"></a>

### Author
Post/authorship-centric version of User. UI can cross-reference user details from its own
cache (for things like admin/bot icons).

Lives in `media.proto` (rather than `users.proto`, where it used to live, or its own
`authors.proto`, split out from `users.proto` for a time) because `Author.avatar` needs
`MediaReference` and `Media`/`MediaReference` need `Author` (see this field&#39;s own doc) --
mutually recursive types belong in the same file, since `protoc` rejects circular *file*
imports even though the recursive *types* themselves are perfectly valid. `users.proto`
(`User.sync_destinations`) and `sync.proto` (`SyncDestination.owner`, `SyncSource.owner`) both
depend on this without depending on each other, via their own `import &#34;media.proto&#34;` (both
already needed it anyway, for `User.avatar`/`Media`-shaped fields).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | Permanent string ID for the user. Will never contain a `@` symbol. |
| username | [string](#string) | optional | Impermanent string username for the user. Will never contain a `@` symbol. |
| avatar | [MediaReference](#rellm-MediaReference) | optional | The user&#39;s avatar. |
| real_name | [string](#string) | optional |  |
| permissions | [Permission](#rellm-Permission) | repeated |  |






<a name="rellm-GetMediaRequest"></a>

### GetMediaRequest
Valid GetMediaRequest formats:
- `{user_id: abc123}` - Gets the media of the given user that the current user can see. IE:
    - *all* of the current user&#39;s own media
    - `GLOBAL_PUBLIC` media for the user if the current user is not logged in.
    - `SERVER_PUBLIC` media for the user if the current user is logged in.
    - `LIMITED` media for the user if the current user is following the user.
- `{media_id: abc123}` - Gets the media with the given ID, if visible to the current user.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| media_id | [string](#string) | optional | Returns the single media item with the given ID. |
| user_id | [string](#string) | optional | Returns all media items for the given user. |
| page | [uint32](#uint32) |  |  |






<a name="rellm-GetMediaResponse"></a>

### GetMediaResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| media | [Media](#rellm-Media) | repeated |  |
| has_next_page | [bool](#bool) |  |  |






<a name="rellm-Media"></a>

### Media
A Rellm `Media` message represents a single media item, such as a photo or video.
Media data is deliberately *not accessible from the gRPC API*. Instead, the client
should fetch media from `http[s]://my.rellm.instance/media/{id}`, unless `url` is set,
in which case that URL should be used instead (used for media Rellm doesn&#39;t store
locally, e.g. from federated ActivityPub/Mastodon or AT Protocol/Bluesky content).

Media items may be created with a HTTP POST to `http[s]://my.rellm.instance/media`
along with an &#34;Authorization&#34; header (your access token) and a &#34;Content-Type&#34; header.
On success, the endpoint will return the media ID in plaintext.

`POST /media` supports the following headers:
- `Content-Type` - The MIME content type of the media item.
- `Filename` - An optional title for the media item.
- `Authorization` - Rellm Access Token for the user. Required, but may be supplied in `Cookies`.
- `Cookies` - Standard web cookies. The `rellm_access_token` cookie may be used for authentication.

`GET /media/{id}` supports the following:
- **Headers**:
    - `Authorization` - Rellm Access Token for the user. May also be supplied in `Cookies` or via query parameter.
    - `Cookies` - Standard web cookies. The `rellm_access_token` cookie may be used for authentication.
- **Query Parameters**:
    - `authorization` - Rellm Access Token for the user. May also be supplied in the `Cookies` or `Authorization` headers.
- Fetching media without authentication requires that it has `GLOBAL_PUBLIC` visibility.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The ID of the media item. |
| author | [Author](#rellm-Author) | optional | The user who created the media item. |
| name | [string](#string) | optional | An optional title for the media item. |
| description | [string](#string) | optional | An optional description for the media item. |
| visibility | [Visibility](#rellm-Visibility) |  | Visibility of the media item. |
| moderation | [Moderation](#rellm-Moderation) |  | Moderation of the media item. |
| generated | [bool](#bool) |  | Indicates the media was generated by the server rather than uploaded manually by a user. |
| processed | [bool](#bool) |  | Media is generally stored as-is on upload. When background jobs process and compress the media, this flag is set to true. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| metadata | [MediaMetadata](#rellm-MediaMetadata) |  |  |
| url | [string](#string) | optional | An external URL to fetch the media from, in lieu of `/media/{id}`. Used for representing media owned by other protocols/servers (e.g. ActivityPub/Mastodon, AT Protocol/Bluesky) that Rellm does not store locally. If unset, clients fall back to `/media/{id}`. |
| sizes | [MediaSize](#rellm-MediaSize) | repeated | Every stored copy of this media item&#39;s bytes -- the original upload (`MEDIA_CONVERSION_ORIGINAL`) plus any auto-generated resized copies (see `convert_media_sizes`&#39;s background job) -- each with its own content type, byte size, and (once known) aspect ratio. Always has at least one `MEDIA_CONVERSION_ORIGINAL` entry unless `url` is set (externally-hosted media has no locally-stored copies at all). The original is tracked here rather than as a separate top-level field so it can eventually be deleted to free space once converted copies exist, while remaining fully accounted for by `User.media_storage_bytes_used` up until that point. |






<a name="rellm-MediaMetadata"></a>

### MediaMetadata
Free-form metadata about a [`Media`](#rellm-Media) item that isn&#39;t queried/filtered on, so doesn&#39;t need its
own columns.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| video_preview_time_ms | [uint64](#uint64) | optional | For video media, how far into the video (in milliseconds) its preview/poster frame should be taken from -- both via a `#t=&lt;seconds&gt;` Media Fragments URI on the `&lt;video&gt;` element&#39;s `src`, and as the timestamp `ffmpeg` seeks to when generating the `VIDEO_PREVIEW_THUMBNAIL_*` poster frames (see `MediaConversion`). Unset defaults to 1s (1000 in ms), or if the video is shorter than 1.5s, the midpoint of the video. Settable via `UpdateMedia`; changing it invalidates (deletes) any existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes, so the `convert_media_sizes` background job regenerates them at the new time. |






<a name="rellm-MediaReference"></a>

### MediaReference
A reference to a media item, designed to be included in other messages as a reference.
Contains the bare minimum data needed to fetch media via the HTTP API and render it,
and the media item&#39;s name (for alt text usage).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The ID of the media item. |
| name | [string](#string) | optional | An optional title for the media item. |
| generated | [bool](#bool) |  | Indicates the media was generated by the server rather than uploaded manually by a user. |
| metadata | [MediaMetadata](#rellm-MediaMetadata) |  |  |
| sizes | [MediaSize](#rellm-MediaSize) | repeated | See `Media.sizes`. |
| url | [string](#string) | optional | An external URL to fetch the media from, in lieu of `/media/{id}`. See `Media.url`. If unset, clients fall back to `/media/{id}`. |
| description | [string](#string) | optional |  |
| author | [Author](#rellm-Author) | optional | The user who created the media item. See `Media.author`. Included here (unlike most other `MediaReference` fields, which are deliberately pared down from `Media`) so clients that only ever see a `MediaReference` -- e.g. a `Post.media` item -- can still tell whether the current viewer owns it, without a separate `Media` lookup. |






<a name="rellm-MediaSize"></a>

### MediaSize
One stored copy of a `Media` item&#39;s bytes -- either its untouched original upload
(`MEDIA_CONVERSION_ORIGINAL`) or an auto-generated resized copy, as produced by the
`convert_media_sizes` background job. Fields are tracked per-size (rather than once on `Media`
itself) so that a future conversion producing a different kind of derived copy -- e.g. a
`image/jpeg` poster frame for a `video/mp4` original, or a differently-cropped aspect ratio --
can vary any of them independently of the original.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| conversion | [MediaConversion](#rellm-MediaConversion) |  | Which copy this is -- the untouched original, or one of the auto-generated resized copies. |
| size_bytes | [uint64](#uint64) |  | This copy&#39;s size on disk/in MinIO, in bytes. Summed (across every size, of every Media a user owns) into `User.media_storage_bytes_used`. |
| aspect_ratio | [float](#float) | optional | Width divided by height. Set by the `convert_media_sizes` background job once it&#39;s able to read the media&#39;s dimensions (via ImageMagick/ffprobe); unset until then. |
| content_type | [string](#string) |  | The MIME content type of this copy specifically. Usually identical across every size of a given `Media`, but not guaranteed to be -- e.g. a future video-thumbnail conversion could produce an `image/jpeg` size for a `video/mp4` original. |





 


<a name="rellm-MediaConversion"></a>

### MediaConversion
Which stored copy of a `Media` item&#39;s bytes a `MediaSize` represents.

| Name | Number | Description |
| ---- | ------ | ----------- |
| MEDIA_CONVERSION_ORIGINAL | 0 | The untouched original upload. |
| MEDIA_CONVERSION_SMALL | 1 | Resized to fit within 320x320 px, preserving aspect ratio (never upscaled). |
| MEDIA_CONVERSION_MEDIUM | 2 | Resized to fit within 800x800 px, preserving aspect ratio (never upscaled). |
| MEDIA_CONVERSION_LARGE | 3 | Resized to fit within 1600x1600 px, preserving aspect ratio (never upscaled). |
| VIDEO_PREVIEW_THUMBNAIL_SMALL | 5 | For video media only: a `image/jpeg` poster frame captured (via `ffmpeg`) at `MediaMetadata.video_preview_time_ms`, resized to fit within 320x320 px, preserving aspect ratio (never upscaled) -- same dimension tier as `MEDIA_CONVERSION_SMALL`, just a still frame of the video rather than a resized copy of it. Regenerated by the same `convert_media_sizes` background job; deleted (and marked for regeneration) whenever `UpdateMedia` changes `video_preview_time_ms`, since the existing frame no longer matches the requested time. |
| VIDEO_PREVIEW_THUMBNAIL_MEDIUM | 6 | Same as `VIDEO_PREVIEW_THUMBNAIL_SMALL`, but resized to fit within 800x800 px -- the `MEDIA_CONVERSION_MEDIUM` tier. |
| VIDEO_PREVIEW_THUMBNAIL_LARGE | 7 | Same as `VIDEO_PREVIEW_THUMBNAIL_SMALL`, but resized to fit within 1600x1600 px -- the `MEDIA_CONVERSION_LARGE` tier. |


 

 

 



<a name="messages-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## messages.proto



<a name="rellm-GetMessagesRequest"></a>

### GetMessagesRequest
Request to get messages from the server. The request may be filtered by message ID, search text, or creation time.
All non-text-search requests return messages in reverse chronological order (newest first). 
Text search requests return messages in order of relevance to the search text.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| listing_type | [MessageListingType](#rellm-MessageListingType) |  | The type of message listing to return. Required. |
| message_id | [string](#string) | optional | Returns the single message with the given ID (assuming the user has access to it). |
| message_group_id | [string](#string) | optional | Returns messages that are part of the given messaging group (assuming the user has access to it). |
| search_text | [string](#string) | optional | Full-text search query, matched against the sender&#39;s username/real name and the message&#39;s subject and body. Required (and only used) when `listing_type` is `TEXT_SEARCH`. |
| sent_before | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Request to only return posts that were published or created before the given timestamp. |
| from_email | [string](#string) | optional | Returns messages (assuming the user has access to each) whose email &#34;from&#34; header exactly matches the given value - i.e. `Message.from` as returned by a previous response. Meant for expanding the &#34;sender&#34; grouping a client falls back to when `Message.messaging_group` isn&#39;t set (see that field&#39;s own doc comment): unlike `message_group_id`, there&#39;s no server-side group backing this, so it&#39;s just a straight filter, not an access-controlled entity lookup. Since `from` is unauthenticated/spoofable (see this file&#39;s own top-level doc comment), so is this filter - it matches whatever string the sender&#39;s email client sent, nothing more. |






<a name="rellm-GetMessagesResponse"></a>

### GetMessagesResponse
Response to a [`GetMessagesRequest`](#rellm-GetMessagesRequest), containing the requested messages.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| messages | [Message](#rellm-Message) | repeated | The messages that match the request. May be empty if no messages match. May be shortened to a server-defined limit, dependent on service version, configuration, load, etc. |






<a name="rellm-GetPushSubscriptionStatusRequest"></a>

### GetPushSubscriptionStatusRequest
Checks whether the current user has already registered a given Web Push subscription endpoint.
See [`GetPushSubscriptionStatus`](#grpc-api-GetPushSubscriptionStatus)&#39;s own RPC doc comment.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| endpoint | [string](#string) |  | The Web Push subscription endpoint URL to check, as given by `PushManager.subscribe()`. |






<a name="rellm-GetPushSubscriptionStatusResponse"></a>

### GetPushSubscriptionStatusResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| registered | [bool](#bool) |  | Whether the current user has a [`PushSubscription`](#rellm-PushSubscription) registered for this exact `endpoint`. |






<a name="rellm-MarkMessagesReadRequest"></a>

### MarkMessagesReadRequest
Marks (or unmarks) one or more Messages as read by the calling user, e.g. every message in a
thread once it&#39;s been opened. *Authenticated* - read status is inherently personal, so there&#39;s
no anonymous variant the way [`SendMessage`](#grpc-api-SendMessage) has one.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| unread | [bool](#bool) |  | If `false` (the default), the request is to mark the messages as read. If `true`, marks them (back) as unread instead - e.g. an explicit &#34;mark unread&#34; action on an already-read message. |
| message_ids | [string](#string) | repeated | The Messages to mark read/unread. The caller must have the same access to each of them [`GetMessages`](#grpc-api-GetMessages) would require (sender, a `messaging_group` member, a Bcc recipient, or an admin) - see [`MarkMessagesRead`](#grpc-api-MarkMessagesRead)&#39;s own RPC doc comment. A message id the caller doesn&#39;t have access to fails the whole request (see that RPC&#39;s own doc on atomicity) rather than silently skipping it. |






<a name="rellm-MarkMessagesReadResponse"></a>

### MarkMessagesReadResponse
Response to a [`MarkMessagesReadRequest`](#rellm-MarkMessagesReadRequest) - one [`MessageRead`](#rellm-MessageRead) per `message_ids` entry, in the
same order, each reflecting that message&#39;s own read/unread result (see `MarkMessagesReadRequest.unread`).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| message_reads | [MessageRead](#rellm-MessageRead) | repeated |  |






<a name="rellm-Message"></a>

### Message
A Rellm `Message` represents a single message/email sent to one or more recipients
(really, &#34;zero or more&#34;, as the design incorporates undeliverable messages).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The ID of the message. |
| sender | [Author](#rellm-Author) | optional | The sender of the message. Note that this is *purported* (we don&#39;t protect against spoofing). |
| messaging_group | [MessagingGroup](#rellm-MessagingGroup) | optional | Note that, on the backend, every message actually has a messaging group. From the client&#39;s perspective, if messaging_group is not set, you were BCC&#39;ed on the message and don&#39;t have access to the messaging group. |
| body_text | [string](#string) |  | The body text of the message. For email messages, this is the email body. |
| subject | [string](#string) | optional | Subject of the message. For email messages, this is the email subject. |
| email_message_id | [string](#string) | optional | If this message derived from an email, the original email&#39;s message ID (RFC 5322). Used to prevent duplicate messages from being created when the same email is sent multiple times. |
| from | [string](#string) | optional | If this message derived from an email, the original email&#39;s &#34;from&#34; address. |
| to | [string](#string) | optional | If this message derived from an email, the original email&#39;s &#34;to&#34; address. |
| cc | [string](#string) | optional | If this message derived from an email, the original email&#39;s &#34;cc&#34; address. |
| bcc | [string](#string) | optional | If this message derived from an email, the original email&#39;s &#34;bcc&#34; address. |
| current_user_read | [MessageRead](#rellm-MessageRead) | optional | Whether/when *this response&#39;s viewer* has read the message - unset means unread. Always reflects the currently-authenticated caller&#39;s own read status (via [`MarkMessagesRead`](#grpc-api-MarkMessagesRead)), even when browsing `ALL_SYSTEM_MESSAGES(_TEXT_SEARCH)` as an admin: it&#39;s a personal &#34;have I seen this&#34; marker, not tied to whichever user this response happens to be showing `messaging_group` for. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the message was created. |






<a name="rellm-MessageRead"></a>

### MessageRead
Records that a user has read a particular Message - one row (conceptually; see the composite
`message_id`/`user_id` key on the backing table) per (Message, user) that&#39;s ever been marked
read. Only ever surfaced back to the user it belongs to, as `Message.current_user_read` - there&#39;s
no RPC to see *other* users&#39; read status on a Message.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| message_id | [string](#string) |  |  |
| user_id | [string](#string) |  |  |
| read_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When the message was marked read. Always set on a [`MessageRead`](#rellm-MessageRead) returned from [`MarkMessagesRead`](#grpc-api-MarkMessagesRead) - including a `{ unread: true }` call, where it&#39;s simply the time of that unmark request, not a meaningful &#34;last read&#34; timestamp (there&#39;s no longer a row for it to come from at that point). |






<a name="rellm-MessagingGroup"></a>

### MessagingGroup
A group of users who are participating in a conversation.
Most servers will probably have a (dynamically created) &#34;empty group&#34; for an email like
`not_a_user@my_rellm_instance.com`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The ID of the messaging group. |
| members | [Author](#rellm-Author) | repeated | The users who are members of the group. Note that this is a superset of the users who are |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the group was created. |






<a name="rellm-PushSubscription"></a>

### PushSubscription
A browser&#39;s Web Push subscription (see https://developer.mozilla.org/en-US/docs/Web/API/Push_API),
registered so the server can push new-Message notifications to it even while the browser tab is
closed. Only ever surfaced back to the user who registered it - there&#39;s no RPC to list other
users&#39; subscriptions.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The ID of the subscription. |
| endpoint | [string](#string) |  | The Web Push subscription endpoint URL, as given by `PushManager.subscribe()`. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the subscription was registered. |






<a name="rellm-RegisterPushSubscriptionRequest"></a>

### RegisterPushSubscriptionRequest
Registers (or re-registers) a browser&#39;s Web Push subscription for the current user, so new
Messages sent/delivered to them push a notification even while the browser tab is closed.
See [`RegisterPushSubscription`](#grpc-api-RegisterPushSubscription)&#39;s own RPC doc comment.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| endpoint | [string](#string) |  | The Web Push subscription endpoint URL, as given by `PushManager.subscribe()`. |
| p256dh_key | [string](#string) |  | The subscription&#39;s `p256dh` key (base64url), as given by `PushSubscription.getKey(&#39;p256dh&#39;)`. |
| auth_key | [string](#string) |  | The subscription&#39;s `auth` key (base64url), as given by `PushSubscription.getKey(&#39;auth&#39;)`. |






<a name="rellm-SendMessageRequest"></a>

### SendMessageRequest
Request to create a new message.
The server will create a new messaging group for the message, and send it to the given recipients.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| to_user_ids | [string](#string) | repeated |  |
| subject | [string](#string) | optional |  |
| body_text | [string](#string) | optional |  |






<a name="rellm-UnregisterPushSubscriptionRequest"></a>

### UnregisterPushSubscriptionRequest
Unregisters a browser&#39;s Web Push subscription for the current user, e.g. on logout or when
`PushManager.subscribe()` reports the subscription as no longer valid. See
[`UnregisterPushSubscription`](#grpc-api-UnregisterPushSubscription)&#39;s own RPC doc comment.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| endpoint | [string](#string) |  | The Web Push subscription endpoint URL to unregister, as previously passed to [`RegisterPushSubscription`](#grpc-api-RegisterPushSubscription). |





 


<a name="rellm-MessageListingType"></a>

### MessageListingType


| Name | Number | Description |
| ---- | ------ | ----------- |
| PERSONAL_MESSAGES | 0 | Gets messages sent to the current user, and messages (purportedly) sent by the user. |
| PERSONAL_MESSAGES_TEXT_SEARCH | 1 | Gets messages sent to the current user, and messages (purportedly) sent by the user, that match the given search text. Returns results in order of relevance to the search text. |
| ALL_SYSTEM_MESSAGES | 10 | Gets all messages on the server (to a limit), including those sent to other users. Requires admin privileges. |
| ALL_SYSTEM_MESSAGES_TEXT_SEARCH | 11 |  |


 

 

 



<a name="posts-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## posts.proto



<a name="rellm-DeletePostSyncDestinationRequest"></a>

### DeletePostSyncDestinationRequest
Removes a single Post&#39;s sync (cross-post) to one SyncDestination - the reverse of [`SyncPost`](#grpc-api-SyncPost).
Does not delete the post already made on the destination (e.g. the Facebook Page post), only the local sync record.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| post_id | [string](#string) |  | The Post to un-sync. |
| sync_destination_id | [string](#string) |  | The SyncDestination to un-sync it from. |






<a name="rellm-GetGroupPostsRequest"></a>

### GetGroupPostsRequest
Used for getting context about [`GroupPost`](#rellm-GroupPost)s of an existing [`Post`](#rellm-Post).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| post_id | [string](#string) |  | The ID of the post to get [`GroupPost`](#rellm-GroupPost)s for. |
| group_id | [string](#string) | optional | The ID of the group to get [`GroupPost`](#rellm-GroupPost)s for. |






<a name="rellm-GetGroupPostsResponse"></a>

### GetGroupPostsResponse
Used for getting context about [`GroupPost`](#rellm-GroupPost)s of an existing [`Post`](#rellm-Post).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| group_posts | [GroupPost](#rellm-GroupPost) | repeated | The [`GroupPost`](#rellm-GroupPost)s for the given [`Post`](#rellm-Post) or [`Group`](#rellm-Group). |






<a name="rellm-GetPostsRequest"></a>

### GetPostsRequest
Valid GetPostsRequest formats:

- `{[listing_type: AllAccessiblePosts]}`
    - Get ServerPublic/GlobalPublic posts you can see based on your authorization (or lack thereof).
- `{listing_type:MyGroupsPosts|FollowingPosts}`
    - Get posts from groups you&#39;re a member of or from users you&#39;re following. Authorization required.
- `{post_id:}`
    - Get one post ,including preview data/
- `{post_id:, reply_depth: 1}`
    - Get replies to a post - only support for replyDepth=1 is done for now though.
- `{listing_type: MyGroupsPosts|[`GroupPost`](#rellm-GroupPost)sPendingModeration, group_id:}`
    - Get posts/posts needing moderation for a group. Authorization may be required depending on group visibility.
- `{author_user_id:, group_id:}`
    - Get posts by a user for a group. (TODO)
- `{listing_type: AuthorPosts, author_user_id:}`
    - Get posts by a user. (TODO)
- `{listing_type: TextSearch, search_text:}`
    - Full-text search across accessible posts&#39; author username/real name, title, link, and content.
    - `{listing_type: TextSearch, search_text:, author_user_id:}` scopes the search to one author.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| post_id | [string](#string) | optional | Returns the single post with the given ID. |
| author_user_id | [string](#string) | optional | Limits results to those by the given author user ID. |
| group_id | [string](#string) | optional | Limits results to those in the given group ID. |
| reply_depth | [uint32](#uint32) | optional | Only supported for depth=2 for now. |
| context | [PostContext](#rellm-PostContext) | optional | Only POST and REPLY are supported for now. |
| post_ids | [string](#string) | optional | Returns expanded posts with the given IDs. |
| listing_type | [PostListingType](#rellm-PostListingType) |  | The listing type of the request. See [`PostListingType`](#rellm-PostListingType) for more info. |
| page | [uint32](#uint32) |  | The page of results to return. Defaults to 0. |
| search_text | [string](#string) | optional | Full-text search query, matched against the author&#39;s username/real name and the post&#39;s title/link/content. Required (and only used) when `listing_type` is `TEXT_SEARCH`. |
| published_or_created_before | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Request to only return posts that were published or created before the given timestamp. |






<a name="rellm-GetPostsResponse"></a>

### GetPostsResponse
Used for getting posts.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| posts | [Post](#rellm-Post) | repeated | The posts returned by the request. |






<a name="rellm-GroupPost"></a>

### GroupPost
A `GroupPost` is a cross-post of a [`Post`](#rellm-Post) to a [`Group`](#rellm-Group). It contains
information about the moderation of the post in the group, as well as
the time it was cross-posted and the user who did the cross-posting.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| group_id | [string](#string) |  | The ID of the group this post is in. |
| post_id | [string](#string) |  | The ID of the post. |
| user_id | [string](#string) |  | **Deprecated.** Deprecated.** Prefer to use `shared_by`. The ID of the user who cross-posted the post. |
| group_moderation | [Moderation](#rellm-Moderation) |  | The moderation of the post in the group. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the post was cross-posted. |
| shared_by | [Author](#rellm-Author) |  | Author info for the user who cross-posted the post. |






<a name="rellm-Post"></a>

### Post
A `Post` is a message that can be posted to the server. Its `visibility`
as well as any associated [`GroupPost`](#rellm-GroupPost)s and [`UserPost`](#rellm-UserPost)s determine what users
see it and where.

`Post`s are also a fundamental unit of the system. They provide a building block
of Visibility and Moderation management that is used throughout Posts, Replies, Events,
and Occasions.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Unique ID of the post. |
| author | [Author](#rellm-Author) | optional | The author of the post. This is a smaller version of User. |
| reply_to_post_id | [string](#string) | optional | If this is a reply, this is the ID of the post it&#39;s replying to. |
| title | [string](#string) | optional | The title of the post. This is invalid for replies. |
| link | [string](#string) | optional | The link of the post. This is invalid for replies. |
| content | [string](#string) | optional | The content of the post. This is required for replies. |
| response_count | [int32](#int32) |  | The number of responses (replies *and* replies to replies, etc.) to this post. |
| reply_count | [int32](#int32) |  | The number of *direct* replies to this post. |
| group_count | [int32](#int32) |  | The number of groups this post is in. |
| media | [MediaReference](#rellm-MediaReference) | repeated | List of Media IDs associated with this post. Order is preserved. |
| media_generated | [bool](#bool) |  | Flag indicating whether Media has been generated for this Post. Currently previews are generated for any Link post. |
| embed_link | [bool](#bool) |  | Flag indicating |
| shareable | [bool](#bool) |  | Flag indicating a `LIMITED` or `SERVER_PUBLIC` post can be shared with groups and individuals, and a `DIRECT` post can be shared with individuals. |
| context | [PostContext](#rellm-PostContext) |  | Context of the Post (`POST`, `REPLY`, `EVENT`, or `OCCASION`.) |
| visibility | [Visibility](#rellm-Visibility) |  | The visibility of the Post. |
| moderation | [Moderation](#rellm-Moderation) |  | The moderation of the Post. |
| post_media_layout | [PostMediaLayout](#rellm-PostMediaLayout) |  | The desired end-user layout of Media attached to the post. |
| current_group_post | [GroupPost](#rellm-GroupPost) | optional | If the Post was retrieved from GetPosts with a group_id, the GroupPost metadata may be returned along with the Post. |
| replies | [Post](#rellm-Post) | repeated | Hierarchical replies to this post. There will never be more than `reply_count` replies. However, there may be fewer than `reply_count` replies if some replies are hidden by moderation or visibility. Replies are not generally loaded by default, but can be added to Posts in the frontend. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the post was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the post was last updated. |
| published_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the post was published (its visibility first changed to `SERVER_PUBLIC` or `GLOBAL_PUBLIC`). |
| last_activity_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the post was last interacted with (replied to, etc.) |
| unauthenticated_star_count | [int64](#int64) |  | The number of unauthenticated stars on the post. |
| sync_destinations | [SyncDestinationStatus](#rellm-SyncDestinationStatus) | repeated | SyncDestinations this post has been synced (cross-posted) to, and their status. |
| sync_source | [SyncSource](#rellm-SyncSource) | optional | If the Post was created/is kept in sync from a [`SyncSource`](#rellm-SyncSource) (an ICS Event/Occasion, or an RSS/Atom feed item), this is the source it was synced from. Only its media should be considered editable for such a Post. |






<a name="rellm-SyncPostRequest"></a>

### SyncPostRequest
Syncs (cross-posts) a single Post to one SyncDestination.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| post_id | [string](#string) |  | The Post to sync. |
| sync_destination_id | [string](#string) |  | The SyncDestination to sync it to. |






<a name="rellm-UserPost"></a>

### UserPost
A `UserPost` is a &#34;direct share&#34; of a [`Post`](#rellm-Post) to a [`User`](#rellm-User). Currently unused/unimplemented.
See also: [`DIRECT` `Visibility`](#rellm-Visibility).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The ID of the user the post is shared with. |
| post_id | [string](#string) |  | The ID of the post shared. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the post was shared. |





 


<a name="rellm-PostContext"></a>

### PostContext
Differentiates the context of a Post, as in Rellm&#39;s data models, Post is the &#34;core&#34; type where Rellm consolidates moderation and visibility data and logic.

| Name | Number | Description |
| ---- | ------ | ----------- |
| POST | 0 | &#34;Standard&#34; or &#34;Top-Level&#34; Post. Can have media, a link, a title, and/or content. If provided, its `link` and `title` are permanent. |
| REPLY | 1 | Reply to a `POST`, `REPLY`, `EVENT`, or `OCCASION` Does not support a `link`. Requires a `reply_to_post_id`. |
| EVENT | 2 | Post behind an &#34;Event&#34; (which does not actually have a start/end time - it&#39;s a group of Occasions, at least one, which each do). The Events table should have a row for this Post. Never created by the CreatePost RPC (this is an error); use CreateEvent. These Posts&#39; `link` and `title` fields are modifiable. |
| OCCASION | 3 | An &#34;Occasion&#34; Post (which relates to an event with a start and end time). The Occasions table should have a row for this Post. Never created by the CreatePost RPC (this is an error); use CreateEvent/UpdateEvent to manage Occasions implicitly. These Posts&#39; `link` and `title` fields are modifiable. |
| FEDERATED_REPLY | 10 | A reply to a Post on another server. The post *must* have a link of the format `http[s]://&lt;server/post/&lt;post_id&gt;` in its `link` field. It will not have a `reply_to_post_id` value. |



<a name="rellm-PostListingType"></a>

### PostListingType
A high-level enumeration of general ways of requesting posts.

| Name | Number | Description |
| ---- | ------ | ----------- |
| ALL_ACCESSIBLE_POSTS | 0 | Gets SERVER_PUBLIC and GLOBAL_PUBLIC posts as is sensible. Also usable for getting replies anywhere. |
| FOLLOWING_POSTS | 1 | Returns posts from users the user is following. |
| MY_GROUPS_POSTS | 2 | Returns posts from any group the user is a member of. |
| DIRECT_POSTS | 3 | Returns `DIRECT` posts that are directly addressed to the user. |
| POSTS_PENDING_MODERATION | 4 | Returns posts pending moderation by the server-level mods/admins. |
| TEXT_SEARCH | 5 | Returns posts matching the full-text `search_text` query, scoped the same way ALL_ACCESSIBLE_POSTS is (plus author_user_id, if provided). Requires search_text parameter. |
| GROUP_POSTS | 10 | Returns posts from a specific group. Requires group_id parameter. |
| GROUP_POSTS_PENDING_MODERATION | 11 | Returns pending_moderation posts from a specific group. Requires group_id parameter and user must have group (or server) admin permissions. |



<a name="rellm-PostMediaLayout"></a>

### PostMediaLayout


| Name | Number | Description |
| ---- | ------ | ----------- |
| MEDIA_LAYOUT_STANDARD | 0 |  |
| MEDIA_LAYOUT_DYNAMIC_VERTICAL_SCROLL | 1 |  |


 

 

 



<a name="events-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## events.proto



<a name="rellm-AnonymousAttendee"></a>

### AnonymousAttendee
An anonymous internet user who has RSVP&#39;d to an [`Occasion`](#rellm-Occasion).

(TODO:) The visibility on `AnonymousAttendee` [`ContactMethod`](#rellm-ContactMethod)s should support the `LIMITED` visibility, which will
make them visible to the event creator.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | A name for the anonymous user. For instance, &#34;Bob Gomez&#34; or &#34;The guy on your front porch.&#34; |
| contact_methods | [ContactMethod](#rellm-ContactMethod) | repeated | Contact methods for anonymous attendees. Currently not linked to Contact methods for users. |
| auth_token | [string](#string) | optional | Used to allow anonymous users to RSVP to an event. Generated by the server when an event attendance is upserted for the first time. Subsequent attendance upserts, with the same occasion_id and anonymous_attendee.auth_token, will update existing anonymous attendance records. Invalid auth tokens used during upserts will always create a new [`EventAttendance`](#rellm-EventAttendance). |






<a name="rellm-DeleteOccasionSyncDestinationRequest"></a>

### DeleteOccasionSyncDestinationRequest
Removes a single Occasion&#39;s sync (cross-post) to one SyncDestination - the reverse of [`SyncOccasion`](#grpc-api-SyncOccasion).
Does not delete the post already made on the destination (e.g. the Facebook Page post), only the local sync record.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| occasion_id | [string](#string) |  | The Occasion to un-sync. |
| sync_destination_id | [string](#string) |  | The SyncDestination to un-sync it from. |






<a name="rellm-Event"></a>

### Event
An `Event` is a top-level type used to organize calendar events, RSVPs, and messaging/posting
about the `Event`. Actual time data lies in its `Occasions`.

(Eventually, Rellm Events should also support ticketing.)


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| post | [Post](#rellm-Post) |  | The Post containing the underlying data for the event (title, content, moderation, visibility, etc.). Its [`PostContext`](#rellm-PostContext) should be `EVENT`. An `Event`&#39;s ID *is* its `post.id` - there is no separate surrogate ID. |
| info | [EventInfo](#rellm-EventInfo) |  | Event configuration like whether to allow (anonymous) RSVPs, etc. |
| occasions | [Occasion](#rellm-Occasion) | repeated | A list of occasions for the Event. *Events will only include all occasions if the request is for a single event.* |






<a name="rellm-EventAttendance"></a>

### EventAttendance
Could be called an &#34;RSVP.&#34; Describes the attendance of a user at an [`Occasion`](#rellm-Occasion). Such as:
* A user&#39;s RSVP to an [`Occasion`](#rellm-Occasion) (one of `INTERESTED`, `GOING`, `NOT_GOING`, or , `REQUESTED` (i.e. invited)).
* Invitation status of a user to an [`Occasion`](#rellm-Occasion).
* [`ContactMethod`](#rellm-ContactMethod)-driven management for anonymous RSVPs to an [`Occasion`](#rellm-Occasion).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Unique server-generated ID for the attendance. |
| occasion_id | [string](#string) |  | ID of the [`Occasion`](#rellm-Occasion) the attendance is for. |
| user_attendee | [UserAttendee](#rellm-UserAttendee) |  | If the attendance is non-anonymous, core data about the user. |
| anonymous_attendee | [AnonymousAttendee](#rellm-AnonymousAttendee) |  | If the attendance is anonymous, core data about the anonymous attendee. |
| number_of_guests | [uint32](#uint32) |  | Number of guests including the RSVPing user. (Minimum 1). |
| status | [AttendanceStatus](#rellm-AttendanceStatus) |  | The user&#39;s RSVP to an [`Occasion`](#rellm-Occasion) (one of `INTERESTED`, `REQUESTED` (i.e. invited), `GOING`, `NOT_GOING`) |
| inviting_user_id | [string](#string) | optional | User who invited the attendee. (Not yet used.) |
| private_note | [string](#string) |  | Public note for everyone who can see the event to see. |
| public_note | [string](#string) |  | Private note for the event owner. |
| moderation | [Moderation](#rellm-Moderation) |  | Moderation status for the attendance. Moderated by the [`Event`](#rellm-Event) owner (or [`Occasion`](#rellm-Occasion) owner if applicable). |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the attendance was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the attendance was last updated. |






<a name="rellm-EventAttendances"></a>

### EventAttendances
Response to get RSVP data for an event.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| attendances | [EventAttendance](#rellm-EventAttendance) | repeated | The attendance data for the event, in no particular order. |
| hidden_location | [Location](#rellm-Location) | optional | When `hide_location_until_rsvp_approved` is set, the location of the event. |






<a name="rellm-EventInfo"></a>

### EventInfo
To be used for ticketing, RSVPs, etc.
Stored as JSON in the database.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| allows_rsvps | [bool](#bool) | optional | Whether to allow RSVPs for the event. |
| allows_anonymous_rsvps | [bool](#bool) | optional | Whether to allow anonymous RSVPs for the event. |
| max_attendees | [uint32](#uint32) | optional | Limit the max number of attendees. No effect unless `allows_rsvps` is true. Not yet supported. |
| hide_location_until_rsvp_approved | [bool](#bool) | optional | Hide the location until the user RSVPs (and it&#39;s accepted). From a system perspective, when this is set, Events will not include the [`Location`](#rellm-Location) until the user has RSVP&#39;d. Location will always be returned in EventAttendances if the request for the EventAttendances came from a (logged in or anonymous) user whose attendance is approved (or the event owner). |
| default_rsvp_moderation | [Moderation](#rellm-Moderation) | optional | Default moderation for RSVPs from logged-in users (either `PENDING` or `APPROVED`). Anonymous RSVPs are always moderated (default to `PENDING`). |






<a name="rellm-GetEventAttendancesRequest"></a>

### GetEventAttendancesRequest
Request to get RSVP data for an event.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| occasion_id | [string](#string) |  | The ID of the event to get RSVP data for. |
| anonymous_attendee_auth_token | [string](#string) | optional | If set, and if the token has an RSVP for this even, request that RSVP data in addition to the rest of the RSVP data. (The event creator can always see and moderate anonymous RSVPs.) |






<a name="rellm-GetEventsRequest"></a>

### GetEventsRequest
Request to get Events in a formatted *per-Occasion* structure. i.e. the response will carry duplicate [`Event`](#rellm-Event)s with the same ID
if that [`Event`](#rellm-Event) has multiple [`Occasion`](#rellm-Occasion)s in the time frame the client asked for.

These structured Occasions are ordered by start time unless otherwise specified (specifically, `EventListingType.NEWLY_ADDED_EVENTS`).

Valid GetEventsRequest formats:
- `{[listing_type: PublicEvents]}`                 (TODO: get ServerPublic/GlobalPublic events you can see)
- `{listing_type:MyGroupsEvents|FollowingEvents}`  (TODO: get events for groups joined or user followed; auth required)
- `{post_id:}`                                     (get a single event, by its own Post ID or one of its Occasions&#39; Post IDs)
- `{listing_type: GroupEvents| GroupEventsPendingModeration, group_id:}`
                                                   (TODO: get events/events needing moderation for a group)
- `{author_user_id:, group_id:}`                   (TODO: get events by a user for a group)
- `{listing_type: AuthorEvents, author_user_id:}`  (TODO: get events by a user)


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| author_user_id | [string](#string) | optional | Limits results to those by the given author user ID. |
| group_id | [string](#string) | optional | Limits results to those in the given group ID (via [`GroupPost`](#rellm-GroupPost) association&#39;s for the Event&#39;s internal [`Post`](#rellm-Post)). |
| time_filter | [TimeFilter](#rellm-TimeFilter) | optional | Filters returned [`Occasion`](#rellm-Occasion)s by time. |
| attendee_id | [string](#string) | optional | If set, only returns events that the given user is attending. If `attendance_statuses` is also set, returns events where that user&#39;s status is one of the given statuses. |
| attendance_statuses | [AttendanceStatus](#rellm-AttendanceStatus) | repeated | If set, only return events for which the current user&#39;s attendance status matches one of the given statuses. If `attendee_id` is also set, only returns events where the given user&#39;s status matches one of the given statuses. |
| post_id | [string](#string) | optional | Finds Events for the Post with the given ID. The Post should have a [`PostContext`](#rellm-PostContext) of `EVENT` or `OCCASION`. |
| listing_type | [EventListingType](#rellm-EventListingType) |  | The listing type, e.g. `ALL_ACCESSIBLE_EVENTS`, `FOLLOWING_EVENTS`, `MY_GROUPS_EVENTS`, `DIRECT_EVENTS`, `GROUP_EVENTS`, `GROUP_EVENTS_PENDING_MODERATION`. |
| search_text | [string](#string) | optional | Search text for full-text search. |
| occasion_post_ids | [string](#string) | repeated | Loads multiple events by their occasions&#39; Post IDs - returns one Event per matching Occasion (see GetEventsResponse&#39;s own doc), not the requested Occasion&#39;s whole parent Event&#39;s full occasion list. |
| anonymous_attendee_auth_token | [string](#string) | optional | Auth token proving ownership of an anonymous RSVP, mirroring `GetEventAttendancesRequest.anonymous_attendee_auth_token`. Lets an anonymous attendee&#39;s own (possibly still-`PENDING`) [`EventAttendance`](#rellm-EventAttendance) and its `Occasion.location` (when `EventInfo.hide_location_until_rsvp_approved` is set) surface via each returned `Occasion.attendances`/`current_user_attendance`, same as a logged-in user&#39;s own RSVP does automatically. |






<a name="rellm-GetEventsResponse"></a>

### GetEventsResponse
A list of [`Event`](#rellm-Event)s with a maybe-incomplete (see [`GetEventsRequest`](#rellm-GetEventsRequest)) set of their [`Occasion`](#rellm-Occasion)s.

Note that `GetEventsResponse` may often include duplicate Events with the same ID.
I.E. something like: `{events: [{id: a, occasions: [{id: x}]}, {id: a, occasions: [{id: y}]}, ]}` is a valid response.
This semantically means: &#34;Event A has both occasions X and Y in the time frame the client asked for.&#34;
The client should be able to handle this.

In the React/Tamagui client, this is handled by the Redux store, which
effectively &#34;compacts&#34; all response into its own internal Events store, in a form something like:
`{events: {a: {id: a, occasions: [{id: x}, {id: y}]}, ...}, occasionEventIds: {x:a, y:a}}`.
(In reality it uses `EntityAdapter` which is a bit more complicated, but the idea is the same.)


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| events | [Event](#rellm-Event) | repeated |  |






<a name="rellm-Occasion"></a>

### Occasion
The time-based component of an [`Event`](#rellm-Event). Has a `starts_at` and `ends_at` time,
a [`Location`](#rellm-Location), and an optional [`Post`](#rellm-Post) (and discussion thread) specific to this particular
`Occasion` in addition to the parent [`Event`](#rellm-Event).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| event_id | [string](#string) |  | ID of the parent [`Event`](#rellm-Event) (i.e. the parent `Event.post.id`). |
| post | [Post](#rellm-Post) |  | Optional [`Post`](#rellm-Post) containing alternate title/link/description for this particular Occasion. Its [`PostContext`](#rellm-PostContext) should be `OCCASION`. An `Occasion`&#39;s ID *is* its `post.id` - there is no separate surrogate ID. |
| info | [OccasionInfo](#rellm-OccasionInfo) |  | Additional configuration for this [`Occasion`](#rellm-Occasion) beyond the [`EventInfo`](#rellm-EventInfo) in its parent [`Event`](#rellm-Event). |
| starts_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the event starts (UTC/Timestamp format). |
| ends_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the event ends (UTC/Timestamp format). |
| location | [Location](#rellm-Location) | optional | The location of the event. |
| sync_missing_since | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time since this event &#34;disappeared&#34; from the sync source. It is up to the owner whether this means it should be deleted. |
| attendances | [EventAttendances](#rellm-EventAttendances) | optional | RSVP &#43; invite data for this Occasion. |
| current_user_attendance | [EventAttendance](#rellm-EventAttendance) | optional | If the request was made by a logged-in user, this is the current user&#39;s attendance for this Occasion. |
| sync_destinations | [SyncDestinationStatus](#rellm-SyncDestinationStatus) | repeated | SyncDestinations this Occasion has been synced (cross-posted) to, and their status. |
| timezone | [string](#string) | optional | A time zone for the Occasion. Used when serializing it for, e.g., Facebook or Instagram posts, or generating media. |






<a name="rellm-OccasionInfo"></a>

### OccasionInfo
To be used for ticketing, RSVPs, etc.
Stored as JSON in the database.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| rsvp_info | [OccasionRsvpInfo](#rellm-OccasionRsvpInfo) | optional | RSVP configuration and metadata for the Occasion. |






<a name="rellm-OccasionRsvpInfo"></a>

### OccasionRsvpInfo
Consolidated type for RSVP info for an [`Occasion`](#rellm-Occasion).
Curently, the `optional` counts below are *never* returned by the API.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| allows_rsvps | [bool](#bool) | optional | Overrides `EventInfo.allows_rsvps`, if set, for this Occasion. |
| allows_anonymous_rsvps | [bool](#bool) | optional | Overrides `EventInfo.allows_anonymous_rsvps`, if set, for this Occasion. |
| max_attendees | [uint32](#uint32) | optional | Overrides `EventInfo.max_attendees`, if set, for this Occasion. Not yet supported. |
| going_rsvps | [uint32](#uint32) | optional | The number of users who have RSVP&#39;d to the event. |
| going_attendees | [uint32](#uint32) | optional | The number of attendees who have RSVP&#39;d to the event. (RSVPs may have multiple attendees, i.e. guests.) |
| interested_rsvps | [uint32](#uint32) | optional | The number of users who have signaled interest in the event. |
| interested_attendees | [uint32](#uint32) | optional | The number of attendees who have signaled interest in the event. (RSVPs may have multiple attendees, i.e. guests.) |
| invited_rsvps | [uint32](#uint32) | optional | The number of users who have been invited to the event. |
| invited_attendees | [uint32](#uint32) | optional | The number of attendees who have been invited to the event. (RSVPs may have multiple attendees, i.e. guests.) |






<a name="rellm-SyncOccasionRequest"></a>

### SyncOccasionRequest
Syncs (cross-posts) a single Occasion to one SyncDestination.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| occasion_id | [string](#string) |  | The Occasion to sync. |
| sync_destination_id | [string](#string) |  | The SyncDestination to sync it to. |






<a name="rellm-TimeFilter"></a>

### TimeFilter
Time filter that works on the `starts_at` and `ends_at` fields of [`Occasion`](#rellm-Occasion).
API currently only supports `ends_after`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| starts_after | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Filter to events that start after the given time. |
| ends_after | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Filter to events that end after the given time. |
| starts_before | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Filter to events that start before the given time. |
| ends_before | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Filter to events that end before the given time. |






<a name="rellm-UserAttendee"></a>

### UserAttendee
Wire-identical to [Author](#rellm-Author), but with a different name to avoid confusion.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The user ID of the attendee. |
| username | [string](#string) | optional | The username of the attendee. |
| avatar | [MediaReference](#rellm-MediaReference) | optional | The attendee&#39;s user avatar. |
| real_name | [string](#string) | optional |  |
| permissions | [Permission](#rellm-Permission) | repeated |  |





 


<a name="rellm-AttendanceStatus"></a>

### AttendanceStatus
Occasion attendance statuses. State transitions may generally happen
in any direction, but:
* `REQUESTED` can only be selected if another user invited the user whose attendance is being described.
* `GOING` and `NOT_GOING` cannot be selected if the Occasion has ended (end time is in the past).
* `WENT` and `DID_NOT_GO` cannot be selected if the Occasion has not started (start time is in the future).
`INTERESTED` and `REQUESTED` can apply regardless of whether an event has started or ended.

| Name | Number | Description |
| ---- | ------ | ----------- |
| INTERESTED | 0 | The user is (or was) interested in attending. This is the default status. |
| REQUESTED | 1 | Another user has invited the user to the event. |
| GOING | 2 | The user plans to go to the event, or went to the event. |
| NOT_GOING | 3 | The user does not plan to go to the event, or did not go to the event. |



<a name="rellm-EventListingType"></a>

### EventListingType
The listing type, e.g. `ALL_ACCESSIBLE_EVENTS`, `FOLLOWING_EVENTS`, `MY_GROUPS_EVENTS`, `DIRECT_EVENTS`, `GROUP_EVENTS`, `GROUP_EVENTS_PENDING_MODERATION`.

Events returned are ordered by start time unless otherwise specified (specifically, `NEWLY_ADDED_EVENTS`).

| Name | Number | Description |
| ---- | ------ | ----------- |
| ALL_ACCESSIBLE_EVENTS | 0 | Gets `SERVER_PUBLIC` and `GLOBAL_PUBLIC` events depending on whether the user is logged in, `LIMITED` events from authors the user is following, and `PRIVATE` events owned by, or directly addressed to, the current user. |
| FOLLOWING_EVENTS | 1 | Returns events from users the user is following. |
| MY_GROUPS_EVENTS | 2 | Returns events from any group the user is a member of. |
| DIRECT_EVENTS | 3 | Returns `DIRECT` events that are directly addressed to the user. |
| EVENTS_PENDING_MODERATION | 4 | Returns events pending moderation by the server-level mods/admins. |
| EVENT_TEXT_SEARCH | 5 | Returns posts matching the full-text `search_text` query, scoped the same way ALL_ACCESSIBLE_POSTS is (plus author_user_id, if provided). Requires search_text parameter. |
| GROUP_EVENTS | 10 | Returns events from a specific group. Requires group_id parameterRequires group_id parameter |
| GROUP_EVENTS_PENDING_MODERATION | 11 | Returns pending_moderation events from a specific group. Requires group_id parameter and user must have group (or server) admin permissions. |
| NEWLY_ADDED_EVENTS | 20 | Returns events from either `ALL_ACCESSIBLE_EVENTS` or a specific author (with optional author_user_id parameter). Returned Occasions will be ordered by creation time rather than start time. |


 

 

 



<a name="groups-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## groups.proto



<a name="rellm-GetGroupsRequest"></a>

### GetGroupsRequest
Request to get a group or groups by name or ID.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| group_id | [string](#string) | optional | The ID of the group to get. |
| group_name | [string](#string) | optional | The name of the group to get. |
| group_shortname | [string](#string) | optional | The shortname of the group to get. Group shortname search is case-insensitive. |
| listing_type | [GroupListingType](#rellm-GroupListingType) |  | The group listing type. |
| page | [int32](#int32) | optional | The page of results to get. |






<a name="rellm-GetGroupsResponse"></a>

### GetGroupsResponse
Response to a GetGroupsRequest.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| groups | [Group](#rellm-Group) | repeated | The groups that matched the request. |
| has_next_page | [bool](#bool) |  | Whether there are more groups to get. |






<a name="rellm-GetMembersRequest"></a>

### GetMembersRequest
Request to get members of a group.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| group_id | [string](#string) |  | The ID of the group to get members of. |
| username | [string](#string) | optional | The username of the members to search for. |
| group_moderation | [Moderation](#rellm-Moderation) | optional | The membership status to filter members by. If not specified, all members are returned. |
| page | [int32](#int32) | optional | The page of results to get. |






<a name="rellm-GetMembersResponse"></a>

### GetMembersResponse
Response to a GetMembersRequest.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| members | [Member](#rellm-Member) | repeated | The members that matched the request. |
| has_next_page | [bool](#bool) |  | Whether there are more members to get. |






<a name="rellm-Group"></a>

### Group
`Group`s are a way to organize users and posts (and thus events). They can be used for many purposes,


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | The group&#39;s unique ID. |
| name | [string](#string) |  | Mutable name of the group. Must be unique, such that the derived `shortname` is also unique. |
| shortname | [string](#string) |  | Immutable shortname of the group. Derived from changes to `name` when the [`Group`](#rellm-Group) is updated. |
| description | [string](#string) |  | A description of the group. |
| avatar | [MediaReference](#rellm-MediaReference) | optional | An avatar for the group. |
| default_membership_permissions | [Permission](#rellm-Permission) | repeated | The default permissions for new members of the group. |
| default_membership_moderation | [Moderation](#rellm-Moderation) |  | The default moderation for new members of the group. Valid values are PENDING (requires a moderator to let you join) and UNMODERATED. |
| default_post_moderation | [Moderation](#rellm-Moderation) |  | The default moderation for new posts in the group. |
| default_event_moderation | [Moderation](#rellm-Moderation) |  | The default moderation for new events in the group. |
| visibility | [Visibility](#rellm-Visibility) |  | LIMITED visibility groups are only visible to members. PRIVATE groups are only visibile to users with the ADMIN group permission. |
| member_count | [uint32](#uint32) |  | The number of members in the group. |
| post_count | [uint32](#uint32) |  | The number of posts in the group. |
| event_count | [uint32](#uint32) |  | The number of events in the group. |
| non_member_permissions | [Permission](#rellm-Permission) | repeated | The permissions given to non-members of the group. |
| current_user_membership | [Membership](#rellm-Membership) | optional | The membership for the current user, if any. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the group was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the group was last updated. |






<a name="rellm-Member"></a>

### Member
Used when fetching group members using the [`GetMembers`](#grpc-api-GetMembers) RPC.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user | [User](#rellm-User) |  | The user. |
| membership | [Membership](#rellm-Membership) |  | The user&#39;s membership (or join request, or invitation, or both) in the group. |





 


<a name="rellm-GroupListingType"></a>

### GroupListingType
The type of group listing to get.

| Name | Number | Description |
| ---- | ------ | ----------- |
| ALL_GROUPS | 0 | Get all groups (visible to the current user). |
| MY_GROUPS | 1 | Get groups the current user is a member of. |
| REQUESTED_GROUPS | 2 | Get groups the current user has requested to join. |
| INVITED_GROUPS | 3 | Get groups the current user has been invited to. |


 

 

 



<a name="server_configuration-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## server_configuration.proto



<a name="rellm-BirdConfig"></a>

### BirdConfig
Bird (https://bird.com, formerly MessageBird) Config -- an alternative SMS verification
provider to Twilio, with a simpler single-API-key auth model.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| bird_enabled | [bool](#bool) |  |  |
| bird_access_key | [string](#string) |  | The Bird workspace&#39;s API access key. Never serialized once written. |
| bird_from | [string](#string) |  | The originator for outbound verification SMS -- an owned number, alphanumeric sender ID (3-11 chars), or short code, as configured in the Bird workspace. Not secret. |
| bird_region | [string](#string) |  | Which Bird API region to call (&#34;us1&#34; or &#34;eu1&#34;, per Bird&#39;s own regional API hosts). Not secret. Empty defaults to &#34;us1&#34;. |






<a name="rellm-ClusterConductorState"></a>

### ClusterConductorState
The conductor&#39;s live view of currently-held locks - one `ClusterResourceLock` per distinct
holder (a given namespace can appear at most once here - `LockClusterResources` never grants a
`ClusterResource` it&#39;s already granted that same `namespace_id`, and folds any additional
resources into that namespace&#39;s existing entry rather than creating a second one - see that
RPC&#39;s own doc). With a `limits` entry above `1` (see `ClusterResourceLimit`&#39;s own doc), more than
one distinct namespace can hold the *same* `ClusterResource` at once, so there can be more
entries here than there are `ClusterResource` values.
See `ClusterResources.conductor_state`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| locks | [ClusterResourceLock](#rellm-ClusterResourceLock) | repeated | Locks currently held by the conductor. Mutations are only made by `FreeClusterResource` and `LockClusterResource`, not `ConfigureServer`. Changes to locks do *not* produce a new ServerConfiguration version. |
| limits | [ClusterResourceLimit](#rellm-ClusterResourceLimit) | repeated | How many distinct namespaces may concurrently hold each `ClusterResource`&#39;s lock - e.g. only one headless browser at a time, but a handful of `ffmpeg`/ImageMagick conversions in parallel across the cluster, since those are far lighter-weight. Any `ClusterResource` not present here - including on a cluster that&#39;s never had `ConfigureServer` touch `limits` at all - defaults to `1` (see `ClusterTab.elm`&#39;s matching client-side default, shown/edited there as &#34;Browser Instance Limit&#34;/&#34;FFMPEG Process Limit&#34;/&#34;ImageMagick Process Limit&#34;). These are changed by `ConfigureServer` (gated on `EDIT_CLUSTER_SETTINGS`, like the rest of `cluster_resources`) and create a new ServerConfiguration version, unlike `locks` above. |






<a name="rellm-ClusterResourceLimit"></a>

### ClusterResourceLimit
One `ClusterResource`&#39;s configured concurrency limit - a single `resource`/`limit` pairing per
message (both fields are singleton lists in practice; see `ClusterConductorState.limits`&#39;s own
doc for why a `ClusterResource` missing from every `ClusterResourceLimit` here defaults to `1`
rather than `0`).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| resource | [ClusterResource](#rellm-ClusterResource) | repeated |  |
| limit | [uint32](#uint32) | repeated | The number of distinct namespaces that may concurrently hold a lock on `resource`. |






<a name="rellm-ClusterResourceLock"></a>

### ClusterResourceLock
One namespace&#39;s currently-held lock on one or more `ClusterResource`s, and when it acquired
them - shown in `ClusterTab`&#39;s Elm UI so an admin can tell a genuinely stuck lock (acquired
long ago, its holder&#39;s job surely long dead) from one just in normal, brief use, and reach for
`free_all_cluster_resources` (a `bin/` admin tool - see its own doc) accordingly.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| lock_holder_namespace_id | [string](#string) |  | The `namespace_id` (see `ClusterResources.namespace_id`) holding this lock. |
| resources | [ClusterResource](#rellm-ClusterResource) | repeated | Which resources this lock covers. |
| acquired_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When `LockClusterResources` granted this lock. |






<a name="rellm-ClusterResources"></a>

### ClusterResources
Coordinates a small piece of shared, cluster-wide state across multiple independent Rellm
server instances that are otherwise fully isolated from each other (separate databases, separate
[`FederationInfo`](#rellm-FederationInfo), etc.) but happen to run on shared underlying
infrastructure (e.g. several Kubernetes namespaces sharing one small node pool). Currently used
for exactly one thing: making sure only one instance has a headless Chrome/Brave browser open at
any given moment (for generating link preview images), since launching several at once can
exhaust a shared node&#39;s CPU/memory. One participating instance is designated the &#34;conductor&#34; (see
`conductor_host`) and brokers locks via
[`LockClusterResources`](#grpc-api-LockClusterResources)/
[`FreeClusterResources`](#grpc-api-FreeClusterResources); every instance in the cluster --
including the conductor itself - sets its own `ClusterResources` pointing at whichever host
that is.

See `ServerConfiguration.cluster_resources`&#39;s own doc for who can see/edit this.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| namespace_id | [string](#string) |  | Identifies this instance to the conductor - e.g. its Kubernetes namespace. Passed as `LockClusterResourcesRequest.namespace_id`/`FreeClusterResourcesRequest.namespace_id` so the conductor knows who&#39;s asking, and echoed back as `ClusterResourceLock.lock_holder_namespace_id` while this instance holds a lock. By convention (not enforced - see `cluster_shared_secret`&#39;s own doc), the conductor sets its own `namespace_id` equal to its own `conductor_host`; clients (e.g. the Elm `ClusterTab`) use that convention purely for display, to tell &#34;this instance is the conductor&#34; from &#34;some other instance is.&#34; |
| conductor_host | [string](#string) |  | DNS hostname of whichever instance in the cluster is the &#34;conductor&#34; - the single instance that actually brokers [`LockClusterResources`](#grpc-api-LockClusterResources)/ [`FreeClusterResources`](#grpc-api-FreeClusterResources) calls for every other instance (including, by convention, itself - see `conductor_state`). Every instance in the cluster points this at the same host.

Note: callers should resolve this the same way any other cross-server Rellm call does -- via [`GET {conductor_host}/backend_host`](#http-based-client-host-negotiation-for-external-cdns-get-backend_host) first, falling back to `conductor_host` itself - rather than connecting to it directly, in case the conductor sits behind an [`ExternalCDNConfig`](#rellm-ExternalCDNConfig). |
| cluster_shared_secret | [string](#string) |  | Shared secret proving a `LockClusterResources`/`FreeClusterResources` caller is a legitimate member of this cluster, passed as the `cluster-shared-secret` gRPC metadata header (not a request field - there&#39;s no per-user auth involved in these calls at all, just this secret). The receiving server checks it against its own stored `cluster_shared_secret` - that&#39;s the *entire* authorization check: knowing the secret is what makes a caller entitled to treat that server as the conductor, regardless of what that server&#39;s own `namespace_id`/`conductor_host` happen to say (see `namespace_id`&#39;s own doc on that being a display-only convention). Write-only, like [`FacebookAuthConfig.app_secret`](#rellm-FacebookAuthConfig)/ [`WebPushConfig.private_vapid_key`](#rellm-WebPushConfig) - `GetServerConfiguration` never sends the real value back to *any* client (not even an admin), and an empty incoming value on `ConfigureServer` means &#34;leave the stored secret alone,&#34; not &#34;clear it.&#34; Should never be transmitted over a non-TLS connection. |
| conductor_state | [ClusterConductorState](#rellm-ClusterConductorState) | optional | The conductor&#39;s live view of who currently holds each `ClusterResource`&#39;s lock. Only ever populated on whichever instance actually receives (and grants) `LockClusterResources` calls -- in a correctly configured cluster, that&#39;s the one instance every participant points `conductor_host` at (see that field&#39;s own doc), but nothing server-side enforces that; every other instance simply never gets asked to hold this state. Reflects the database directly, updated in place by `LockClusterResources`/`FreeClusterResources` - unlike the rest of `ServerConfiguration`, [`ConfigureServer`](#grpc-api-ConfigureServer) never lets a caller change this, and it isn&#39;t versioned the way other `ConfigureServer` changes are. |






<a name="rellm-CustomHomePage"></a>

### CustomHomePage
Overrides the app&#39;s default `/` page (the combined Events&#43;Posts feed). Unlike a regular
`CustomNavigationTab`, this has no `path` (it&#39;s always `/`) and no `icon`/`title` (the server&#39;s
own name/logo are always shown for the Home tab in the nav, regardless of what it links to).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| tab | [NavigationTab](#rellm-NavigationTab) |  | What `/` renders. Only `HOME_TAB` (the default, combined Events&#43;Posts feed), `EVENTS_TAB`, or `POSTS_TAB` are valid here - never `PEOPLE_TAB`/`ABOUT_TAB`. |
| post_id | [string](#string) |  | Renders a specific Post at `/` instead (e.g. for a custom business site&#39;s landing page). |
| pinned_post_ids | [string](#string) | repeated | Posts pinned to the top of the home page, above its normal content. Loaded the same way `StarredPanel` loads its own starred posts (i.e., conditionally fetching each pinned post&#39;s backing Event alongside it, for posts that are actually about an Event). |
| show_events_strip | [bool](#bool) |  | Shows the Events strip (the same horizontal upcoming-events row the default `HOME_TAB` always shows above its Posts feed) above `target`&#39;s own content. Only meaningful when `target` is `post_id` (pins an Events strip above that single Post); has no effect when `target` is unset/`HOME_TAB` (the strip is already shown) or `POSTS_TAB` (equivalent to just leaving `target` unset). |
| default_events_strip_to_row | [bool](#bool) |  | Whenever an Events strip is shown above other content - `show_events_strip` is set, or `target` is unset/`HOME_TAB` (whose strip is always shown) - whether it defaults to its row/list layout instead of a calendar. Unset defaults to the calendar layout. |
| default_events_strip_calendar_display_mode | [CalendarDisplayMode](#rellm-CalendarDisplayMode) |  | Whenever an Events strip is shown above other content (see `default_events_strip_to_row`&#39;s own doc) and defaults to the calendar layout (`default_events_strip_to_row` is unset), which granularity it opens to. Defaults to `CALENDAR_DISPLAY_WEEK`. |






<a name="rellm-CustomNavigationTab"></a>

### CustomNavigationTab
Either one of the app&#39;s predefined tabs, a Post, or a user profile - reachable at `path`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| tab | [NavigationTab](#rellm-NavigationTab) |  | Links to one of the app&#39;s predefined tabs/pages. |
| post_id | [string](#string) |  | Links to a specific Post (e.g. for a custom business site&#39;s page). |
| is_profile | [bool](#bool) |  | Indicates the custom tab is for an actual user profile - `path` is that user&#39;s username. Ultimately this isn&#39;t very &#34;custom&#34; in terms of the URL scheme, just it being a navigation tab. |
| emoji_icon | [string](#string) |  | Emoji shown as the tab&#39;s icon (e.g. &#34;🎪&#34;). |
| icon_media_id | [string](#string) |  | Media ID (see [`Media`](#rellm-Media) APIs) of an image shown as the tab&#39;s icon. |
| title | [string](#string) | optional | Title shown for the tab. Defaults to the predefined tab&#39;s/Post&#39;s title if unset. |
| path | [string](#string) |  | The path this tab is reachable at, e.g. `gigs` for a band&#39;s `/gigs` link to the Events page, or `weddings` for a Post about wedding offerings. Must be distinct across every entry in `CustomNavigationTabSet.tabs`. Note: `events`, `posts`, `people`, and `about` are reserved -- each may only be used to (redundantly) point back at its own matching predefined tab, never remapped to a different tab or a Post. `/` itself is never reachable this way - it&#39;s overridden via `CustomNavigationTabSet.home` instead. |






<a name="rellm-CustomNavigationTabSet"></a>

### CustomNavigationTabSet
If set, overrides the default tab set for the Elm navigation on a Rellm instance.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| home | [CustomHomePage](#rellm-CustomHomePage) | optional | Overrides the default `/` page. If unset, the default combined Events&#43;Posts feed is used. |
| tabs | [CustomNavigationTab](#rellm-CustomNavigationTab) | repeated | Overrides the default tab set (`EVENTS_TAB`, `POSTS_TAB`, `PEOPLE_TAB`, `ABOUT_TAB`) entirely. Note: existing `/events`, `/posts`, `/people`, and `/about` paths are reserved for their matching predefined tab - see [`CustomNavigationTab`](#rellm-CustomNavigationTab).path&#39;s own doc. `/` itself is overridden via `home` above instead. |
| tab_style | [NavigationTabStyle](#rellm-NavigationTabStyle) |  | How every tab (Home excluded - it always shows the server&#39;s own logo/name) is laid out in the Elm nav. Purely cosmetic: it changes nothing about which tabs exist, their order, or where they link - see `NavigationTabStyle` below. Defaults to `NAVIGATION_TAB_ICON_ONLY` (proto enum value 0) both when `CustomNavigationTabSet` itself is unset and for any config saved before this field existed. |






<a name="rellm-EventSettings"></a>

### EventSettings
Specific settings for Events.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| visible | [bool](#bool) |  | Hide the Events tab from the user with this flag. |
| default_moderation | [Moderation](#rellm-Moderation) |  | Only `UNMODERATED` and `PENDING` are valid. When `UNMODERATED`, user reports may transition status to `PENDING`. When `PENDING`, users&#39; SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not be visible until a moderator approves them. `LIMITED` visiblity posts are always visible to targeted users (who have not blocked the author) regardless of default_moderation. |
| default_visibility | [Visibility](#rellm-Visibility) |  | Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]` as appropriate. |
| alias_singular | [string](#string) | optional | Can be used to rename, e.g., &#34;Event&#34; to &#34;Gig&#34; or &#34;Performance&#34; |
| alias_plural | [string](#string) | optional | Can be used to rename, e.g. &#34;Events&#34; to &#34;Show,&#34; &#34;Game,&#34; &#34;Competition&#34; |
| enable_replies | [bool](#bool) | optional | Works the same as for Posts. |
| calendar_lookback_days | [uint32](#uint32) | optional | How far to look back for the &#34;Upcoming Events&#34; tab in the server&#39;s UI. Defaults to `14`. Servers with fewer events may want to set to a higher value. |
| default_calendar_display_mode | [CalendarDisplayMode](#rellm-CalendarDisplayMode) |  | What the Events Calendar&#39;s default UI mode will be. Defaults to `CALENDAR_DISPLAY_WEEK`. Servers with fewer events may want to set `CALENDAR_DISPLAY_MONTH`, or with more to `CALENDAR_DISPLAY_DAY`. |
| show_started_or_long_events_by_default | [bool](#bool) |  | Affects the Elm UI &#34;▽&#34; button on EventsPages (embedded or no). When this is false, that filter defaults to &#34;on.&#34; When true, that filter defaults to &#34;off.&#34;

For a band site (where you want to show your &#34;true calendar&#34;), this is best set to `true`. For a site where you have lots of event postings, it&#39;s best set to `false`. |






<a name="rellm-ExternalCDNConfig"></a>

### ExternalCDNConfig
Useful for setting your Rellm instance up to run underneath a CDN.
By default, the web client uses `window.location.hostname` to determine the backend server.
If set, the web client will use this value instead. NOTE: Only applies to Tamagui web client for now.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| frontend_host | [string](#string) |  | The domain where the frontend is hosted. For example, jonline.io. Typically your CDN (like Cloudflare) should own the DNS for this domain. |
| backend_host | [string](#string) |  | The domain where the backend is hosted. For example, jonline.io.itsj.online. Typically your Kubernetes provider should own DNS for this domain. |
| secure_media | [bool](#bool) |  | (TODO) When set, the HTTP `GET /media/&lt;id&gt;?&lt;authorization&gt;` endpoint will be disabled by default on the HTTP (non-secure) server that sends data to the CDN. Only requests from IPs in `media_ipv4_allowlist` and `media_ipv6_allowlist` will be allowed. |
| media_ipv4_allowlist | [string](#string) | optional | Whitespace- and/or comma- separated list of IPv4 addresses/ranges to whom media data may be served. Only applicable if `secure_media` is `true`. For reference, Cloudflare&#39;s are at https://www.cloudflare.com/ips-v4. |
| media_ipv6_allowlist | [string](#string) | optional | Whitespace- and/or comma- separated list of IPv6 addresses/ranges to whom media data may be served. Only applicable if `secure_media` is `true`. For reference, Cloudflare&#39;s are at https://www.cloudflare.com/ips-v6. |
| cdn_grpc | [bool](#bool) |  | (TODO) When implemented, this actually changes the whole Rellm protocol (in terms of ports). When enabled, Rellm should *not* server a secure site on HTTPS, and instead serve the Tonic gRPC server there (on port 443). Jonine clients will need to be updated to always seek out a secure client on port 443 when this feature is enabled. This would let Rellm leverage Cloudflare&#39;s DDOS protection and performance on gRPC as well as HTTP. (This is a Cloudflare-specific feature requirement.) |






<a name="rellm-FeatureSettings"></a>

### FeatureSettings
Settings for a feature (e.g. People, Groups, Posts, Events, Media).
Encompasses both the feature&#39;s visibility and moderation settings.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| visible | [bool](#bool) |  | Hide the Posts or Events tab from the user with this flag. |
| default_moderation | [Moderation](#rellm-Moderation) |  | Only `UNMODERATED` and `PENDING` are valid. When `UNMODERATED`, user reports may transition status to `PENDING`. When `PENDING`, users&#39; SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not be visible until a moderator approves them. `LIMITED` visiblity posts are always visible to targeted users (who have not blocked the author) regardless of default_moderation. |
| default_visibility | [Visibility](#rellm-Visibility) |  | Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]` as appropriate. |
| alias_singular | [string](#string) | optional | Can be used to rename, e.g., &#34;Person&#34; to &#34;Contributor&#34; or &#34;Group&#34; to &#34;Community&#34; |
| alias_plural | [string](#string) | optional | Can be used to rename, e.g. &#34;Groups&#34; to &#34;Subtwaddits&#34; or &#34;People&#34; to &#34;Folks&#34; |






<a name="rellm-FreeClusterResourcesRequest"></a>

### FreeClusterResourcesRequest
Releases resources this `namespace_id` previously locked via
[`LockClusterResources`](#grpc-api-LockClusterResources). A no-op (not an error) for any
resource `namespace_id` doesn&#39;t currently hold - e.g. safe to call unconditionally during
cleanup even if the matching lock attempt itself failed or was never confirmed.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| namespace_id | [string](#string) |  | This instance&#39;s own `ClusterResources.namespace_id` - must match whichever `namespace_id` is recorded as the current holder for a resource to actually be released. |
| resources | [ClusterResource](#rellm-ClusterResource) | repeated | Which resources to release. |






<a name="rellm-LockClusterResourcesRequest"></a>

### LockClusterResourcesRequest
See [`LockClusterResources`](#grpc-api-LockClusterResources).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| namespace_id | [string](#string) |  | This instance&#39;s own `ClusterResources.namespace_id`. |
| resources | [ClusterResource](#rellm-ClusterResource) | repeated | Which resources to lock - see the `ClusterResource` enum for what exists. |






<a name="rellm-LockClusterResourcesResponse"></a>

### LockClusterResourcesResponse
See [`LockClusterResources`](#grpc-api-LockClusterResources).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| granted | [bool](#bool) |  | Whether every requested resource was successfully locked for `namespace_id`. `false` means none were locked (never a partial grant) - at least one of them is already held, by namespaces other than this one, by as many distinct holders as its configured `ClusterResourceLimit` allows (see that message&#39;s own doc); see `holder`. There&#39;s no server-side wait/queueing: a caller that gets `false` should back off and call `LockClusterResources` again later. |
| holder | [string](#string) | optional | Set only when `granted` is `false`: one of the namespaces already holding a requested (and therefore denied) resource. |






<a name="rellm-MarketSettings"></a>

### MarketSettings
Whether this server&#39;s `/market` is open -- an explicit, admin-set toggle independent of
`StripeConfig.stripe_enabled` (an admin can configure Stripe credentials without opening the
storefront yet, or temporarily close it without touching those credentials). See
`ServerConfiguration.market_settings`&#39;s own doc on why this lives outside `StripeConfig`: it&#39;s
the one bit that has to stay visible to non-admins for federated multi-server Market browsing to
work at all.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| enabled | [bool](#bool) |  |  |
| stripe_configured | [bool](#bool) |  | Whether Stripe is actually usable right now -- `stripe_config.stripe_enabled` is true AND a `stripe_secret_key` is on file. Computed live on every `GetServerConfiguration` (never read back from whatever was last saved to `market_settings` itself), and -- like `enabled` above -- deliberately never stripped for non-admins: it&#39;s the public &#34;can I actually buy something here&#34; signal a buyer needs (e.g. to grey out `/market/product/:id`&#39;s &#34;Buy&#34; button with a &#34;Stripe is not configured&#34; message) without ever exposing `StripeConfig` itself, which stays admin-only. |






<a name="rellm-MediaSettings"></a>

### MediaSettings
Media is a special type and less customizable than &#34;Features.&#34;


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| visible | [bool](#bool) |  | Hide the Posts or Events tab from the user with this flag. |
| default_moderation | [Moderation](#rellm-Moderation) |  | Only `UNMODERATED` and `PENDING` are valid. When `UNMODERATED`, user reports may transition status to `PENDING`. When `PENDING`, users&#39; SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not be visible until a moderator approves them. `LIMITED` visiblity posts are always visible to targeted users (who have not blocked the author) regardless of default_moderation. |
| default_visibility | [Visibility](#rellm-Visibility) |  | Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]` as appropriate. |
| default_media_allocation_bytes | [uint64](#uint64) |  | Default media storage allocation for newly created users. Defaults to 10MB. |






<a name="rellm-PostSettings"></a>

### PostSettings
Specific settings for Posts.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| visible | [bool](#bool) |  | Hide the Posts tab from the user with this flag. |
| default_moderation | [Moderation](#rellm-Moderation) |  | Only `UNMODERATED` and `PENDING` are valid. When `UNMODERATED`, user reports may transition status to `PENDING`. When `PENDING`, users&#39; SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not be visible until a moderator approves them. `LIMITED` visiblity posts are always visible to targeted users (who have not blocked the author) regardless of default_moderation. |
| default_visibility | [Visibility](#rellm-Visibility) |  | Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]` as appropriate. |
| alias_singular | [string](#string) | optional | Can be used to rename, e.g., &#34;Post&#34; &#34;Highlight&#34; or &#34;Squirt&#34; |
| alias_plural | [string](#string) | optional | Can be used to rename, e.g. &#34;Posts&#34; to &#34;Splurts&#34; or &#34;Memories&#34; |
| enable_replies | [bool](#bool) | optional | Controls whether replies are shown in the UI. Note that users&#39; ability to reply is controlled by the `REPLY_TO_POSTS` permission. |






<a name="rellm-ServerColors"></a>

### ServerColors
Color in ARGB hex format (i.e `0xAARRGGBB`).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| primary | [uint32](#uint32) | optional | App Bar/primary accent color. |
| navigation | [uint32](#uint32) | optional | Nav/secondary accent color. |
| author | [uint32](#uint32) | optional | Color used on author of a post in discussion threads for it. |
| admin | [uint32](#uint32) | optional | Color used on author for admin posts. |
| moderator | [uint32](#uint32) | optional | Color used on author for moderator posts. |






<a name="rellm-ServerConfiguration"></a>

### ServerConfiguration
Configuration for a Rellm server instance.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| server_info | [ServerInfo](#rellm-ServerInfo) | optional | The name, description, logo, color scheme, etc. of the server. |
| federation_info | [FederationInfo](#rellm-FederationInfo) | optional | The federation configuration for the server. |
| anonymous_user_permissions | [Permission](#rellm-Permission) | repeated | Permissions for a user who isn&#39;t logged in to the server. Allows admins to disable certain features for anonymous users. Valid values are `VIEW_USERS`, `VIEW_GROUPS`, `VIEW_POSTS`, and `VIEW_EVENTS`. |
| default_user_permissions | [Permission](#rellm-Permission) | repeated | Default user permissions given to a new user. Users with `MODERATE_USERS` permission can also grant/revoke these permissions for others. Valid values are `VIEW_USERS`, `PUBLISH_USERS_LOCALLY`, `PUBLISH_USERS_GLOBALLY`, `VIEW_GROUPS`, `CREATE_GROUPS`, `PUBLISH_GROUPS_LOCALLY`, `PUBLISH_GROUPS_GLOBALLY`, `JOIN_GROUPS`, `VIEW_POSTS`, `CREATE_POSTS`, `PUBLISH_POSTS_LOCALLY`, `PUBLISH_POSTS_GLOBALLY`, `VIEW_EVENTS`, `CREATE_EVENTS`, `PUBLISH_EVENTS_LOCALLY`, and `PUBLISH_EVENTS_GLOBALLY`. |
| basic_user_permissions | [Permission](#rellm-Permission) | repeated | Permissions grantable by a user with the `GRANT_BASIC_PERMISSIONS` permission. Valid values are `VIEW_USERS`, `PUBLISH_USERS_LOCALLY`, `PUBLISH_USERS_GLOBALLY`, `VIEW_GROUPS`, `CREATE_GROUPS`, `PUBLISH_GROUPS_LOCALLY`, `PUBLISH_GROUPS_GLOBALLY`, `JOIN_GROUPS`, `VIEW_POSTS`, `CREATE_POSTS`, `PUBLISH_POSTS_LOCALLY`, `PUBLISH_POSTS_GLOBALLY`, `VIEW_EVENTS`, `CREATE_EVENTS`, `PUBLISH_EVENTS_LOCALLY`, and `PUBLISH_EVENTS_GLOBALLY`. |
| custom_tabs | [CustomNavigationTabSet](#rellm-CustomNavigationTabSet) | optional |  |
| people_settings | [FeatureSettings](#rellm-FeatureSettings) |  | Configuration for users on the server. If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must* contain `PUBLISH_USERS_GLOBALLY`. |
| group_settings | [FeatureSettings](#rellm-FeatureSettings) |  | Configuration for groups on the server. If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must* contain `PUBLISH_GROUPS_GLOBALLY`. |
| post_settings | [PostSettings](#rellm-PostSettings) |  | Configuration for posts on the server. If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must* contain `PUBLISH_POSTS_GLOBALLY`. |
| event_settings | [EventSettings](#rellm-EventSettings) |  | Configuration for events on the server. If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must* contain `PUBLISH_EVENTS_GLOBALLY`. |
| media_settings | [MediaSettings](#rellm-MediaSettings) |  | Configuration for media on the server. If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must* contain `PUBLISH_MEDIA_GLOBALLY`. |
| market_settings | [MarketSettings](#rellm-MarketSettings) |  | Public, non-secret &#34;is this server&#39;s Market open&#34; signal -- unlike `stripe_config` (which holds real credentials and is Admin-only, see that field&#39;s own doc), this is never stripped for a non-admin/unauthenticated caller. Lets a client decide whether to show this server&#39;s Market section at all (e.g. when browsing a federated list of servers) without needing to be an admin here just to check -- see `rellm.proto`&#39;s own &#34;Federated Markets&#34; doc section. |
| external_cdn_config | [ExternalCDNConfig](#rellm-ExternalCDNConfig) | optional | If set, enables External CDN support for the server. This means that the non-secure HTTP server (on port 80) will *not* redirect to the secure server, and instead serve up Tamagui Web/Flutter clients directly. This allows you to point Cloudflare&#39;s &#34;CNAME HTTPS Proxy&#34; feature at your Rellm server to serve up HTML/CS/JS and Media files with caching from Cloudflare&#39;s CDN. See ExternalCDNConfig for more details on securing this setup. |
| cluster_resources | [ClusterResources](#rellm-ClusterResources) | optional | Cluster-internal coordination state - see `ClusterResources`&#39;s own doc. Visible to any logged-in admin (unlike most fields here, this describes infrastructure topology rather than anything end users need, so it&#39;s stripped entirely from [`GetServerConfiguration`](#grpc-api-GetServerConfiguration) for non-admins/anonymous callers); editing it via [`ConfigureServer`](#grpc-api-ConfigureServer) additionally requires the [`EDIT_CLUSTER_SETTINGS`](#rellm-Permission) permission. |
| private_user_strategy | [PrivateUserStrategy](#rellm-PrivateUserStrategy) |  | Strategy when a user sets their visibility to `PRIVATE`. Defaults to `ACCOUNT_IS_FROZEN`. |
| authentication_features | [AuthenticationFeature](#rellm-AuthenticationFeature) | repeated | (TODO) Allows admins to enable/disable creating accounts and logging in. Eventually, external auth too hopefully! |
| web_push_config | [WebPushConfig](#rellm-WebPushConfig) | optional | Web Push (VAPID) configuration for the server. |
| preferred_verification_apis | [VerificationAPI](#rellm-VerificationAPI) | repeated | A server-preferred order of contact verification APIs. Note: even if this is blank, if twilio_config is enabled, the server should try to verify with Twilio. It&#39;s really only for the case of wanting to switch between multiple SMS/Email providers. Only serialized for admin users. |
| available_verification_apis | [VerificationAPI](#rellm-VerificationAPI) | repeated | Derived from whether TwilioConfig.enabled is true, etc. Serialized to every caller (not admin-only, unlike `preferred_verification_apis`/`twilio_config`) -- this is what a non-admin client should check to decide whether to show verification UI at all, without exposing any provider configuration. |
| twilio_config | [TwilioConfig](#rellm-TwilioConfig) | optional | Twilio Config. Only serialized for admin users. |
| bird_config | [BirdConfig](#rellm-BirdConfig) | optional | Bird (bird.com, formerly MessageBird) Config -- a cheaper Twilio alternative for SMS verification. Only serialized for admin users. |
| stripe_config | [StripeConfig](#rellm-StripeConfig) | optional | Stripe Config, backing the Marketplace (`market.proto`). Only serialized for admin users. |
| telnyx_config | [TelnyxConfig](#rellm-TelnyxConfig) | optional | Telnyx Config -- another alternative SMS verification provider to Twilio (see `TelnyxConfig`&#39;s own doc). Only serialized for admin users. |






<a name="rellm-ServerInfo"></a>

### ServerInfo
User-facing information about the server displayed on the &#34;about&#34; page.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) | optional | Name of the server. |
| short_name | [string](#string) | optional | Short name of the server. Used in URLs, etc. (Currently unused.) |
| description | [string](#string) | optional | Description of the server. |
| privacy_policy | [string](#string) | optional | The server&#39;s privacy policy. Will be displayed during account creation and on the `/about` page. |
| logo | [ServerLogo](#rellm-ServerLogo) | optional | Multi-size logo data for the server. |
| web_user_interface | [WebUserInterface](#rellm-WebUserInterface) | optional | The web UI to use (React/Tamagui (default) vs. Flutter Web) |
| colors | [ServerColors](#rellm-ServerColors) | optional | The color scheme for the server. |
| media_policy | [string](#string) | optional | The media policy for the server. Will be displayed during account creation and on the `/about` page. |
| recommended_server_hosts | [string](#string) | repeated | **Deprecated.** This will be replaced with FederationInfo soon. |






<a name="rellm-ServerLogo"></a>

### ServerLogo
Logo data for the server. Built atop Rellm [`Media` APIs](#rellm-Media).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| squareMediaId | [string](#string) | optional | The media ID for the square logo. |
| squareMediaIdDark | [string](#string) | optional | The media ID for the square logo in dark mode. |
| wideMediaId | [string](#string) | optional | The media ID for the wide logo. |
| wideMediaIdDark | [string](#string) | optional | The media ID for the wide logo in dark mode. |






<a name="rellm-StripeConfig"></a>

### StripeConfig
Stripe credentials backing the Marketplace (`market.proto`). Used both to create Checkout
Sessions/off-session renewal PaymentIntents (`stripe_secret_key`) and to verify incoming
webhook deliveries (`stripe_webhook_signing_secret`).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| stripe_enabled | [bool](#bool) |  |  |
| stripe_secret_key | [string](#string) |  | Stripe Secret Key (starts with `sk_`), used as Bearer auth for all Stripe API calls made by this server (Checkout Session creation, off-session renewal charges). Never serialized once written -- same write-only treatment as `TwilioConfig.twilio_api_key_secret`. |
| stripe_publishable_key | [string](#string) |  | Stripe Publishable Key (starts with `pk_`). Not secret -- kept here (rather than derived from `stripe_secret_key`) so a future client-side Stripe Elements integration has what it needs, even though the current Checkout-based flow doesn&#39;t use it server-side at all. |
| stripe_webhook_signing_secret | [string](#string) |  | Signing secret (starts with `whsec_`) for the `/webhooks/stripe` endpoint, used to verify the `Stripe-Signature` header on incoming webhook deliveries. Never serialized once written -- same write-only treatment as `stripe_secret_key` above. |






<a name="rellm-TelnyxConfig"></a>

### TelnyxConfig
Telnyx (https://telnyx.com) Config -- an alternative SMS verification provider to Twilio, with a
simpler single-API-key auth model like Bird&#39;s (see `BirdConfig`&#39;s own doc).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| telnyx_enabled | [bool](#bool) |  |  |
| telnyx_api_key | [string](#string) |  | The Telnyx v2 API Key (starts with `KEY`), used as Bearer auth for Telnyx&#39;s Messaging API (`POST /v2/messages`). Never serialized once written -- same write-only treatment as `TwilioConfig.twilio_api_key_secret`/`BirdConfig.bird_access_key`. |
| telnyx_from_number | [string](#string) |  | The Telnyx-provisioned sending number for outbound verification SMS (E.164, e.g. a toll-free number). Not secret. |
| telnyx_messaging_profile_id | [string](#string) |  | The Telnyx Messaging Profile ID that `telnyx_from_number` is assigned to -- required by Telnyx&#39;s Messaging API to actually send (`messaging_profile_id` on `POST /v2/messages`). Not secret. |






<a name="rellm-TwilioConfig"></a>

### TwilioConfig
Twilio credentials, authenticated via a Twilio **API Key** (`twilio_api_key_sid`/
`twilio_api_key_secret`) -- deliberately *not* the account&#39;s own Auth Token. A server&#39;s Auth
Token is a single unscoped, unrevocable-without-rotating-everything credential with full access
to the whole Twilio account; an API Key is its own separate, individually-revocable credential
pair meant for exactly this kind of integration. `twilio_account_sid` is still required (Twilio
resource URLs are always addressed by the actual Account SID), but it is *not* used to
authenticate -- only the API Key SID/Secret pair is. See
https://www.twilio.com/docs/iam/api-keys/restricted-api-keys for the recommended
permission when creating one: `/twilio/messaging/messages/create` (nothing else is needed just
to send verification SMS).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| twilio_enabled | [bool](#bool) |  |  |
| twilio_account_sid | [string](#string) |  | The Twilio Account SID (starts with `AC`). Used only in the API&#39;s URL path -- *never* as an authentication credential. Public (among admins) -- freely serialized. |
| twilio_api_key_sid | [string](#string) |  | The Twilio API Key&#39;s SID (starts with `SK`), used as the Basic Auth username. Public (among admins) -- freely serialized; it&#39;s useless without the Secret below, same as a username alone. |
| twilio_api_key_secret | [string](#string) |  | The Twilio API Key&#39;s Secret, used as the Basic Auth password. Never serialized once written. |
| twilio_from_number | [string](#string) |  | The Twilio-provisioned sending number for outbound verification SMS. Not secret. |






<a name="rellm-WebPushConfig"></a>

### WebPushConfig
Web Push (VAPID) configuration for the server.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| public_vapid_key | [string](#string) |  | Public VAPID key for the server. |
| private_vapid_key | [string](#string) |  | Private VAPID key for the server. *Never serialized to the client.* Admins: Edit this in the database&#39;s JSONB column directly. |





 


<a name="rellm-AuthenticationFeature"></a>

### AuthenticationFeature
Authentication features that can be enabled/disabled by the server admin.

| Name | Number | Description |
| ---- | ------ | ----------- |
| AUTHENTICATION_FEATURE_UNKNOWN | 0 | An authentication feature that is not known to the server. (Likely, the client and server use different versions of the Rellm protocol.) |
| CREATE_ACCOUNT | 1 | Users can sign up for an account. |
| LOGIN | 2 | Users can sign in with an existing account. |



<a name="rellm-CalendarDisplayMode"></a>

### CalendarDisplayMode
The Events Calendar&#39;s default UI granularity.

| Name | Number | Description |
| ---- | ------ | ----------- |
| CALENDAR_DISPLAY_WEEK | 0 | Shows a 7-day week at a time. Good default for most servers. |
| CALENDAR_DISPLAY_MONTH | 1 | Shows a full month at a time. Better for servers with fewer events. |
| CALENDAR_DISPLAY_DAY | 3 | Shows a single day at a time. Better for servers with many events. |



<a name="rellm-ClusterResource"></a>

### ClusterResource
A resource `ClusterResources.conductor_host` can hand out an exclusive, cluster-wide lock on
via [`LockClusterResources`](#grpc-api-LockClusterResources)/
[`FreeClusterResources`](#grpc-api-FreeClusterResources).

| Name | Number | Description |
| ---- | ------ | ----------- |
| CLUSTER_RESOURCE_BROWSER | 0 | The ability to launch a headless Chrome/Brave browser - see `ClusterResources`&#39;s own doc for why more than one running at once across a cluster&#39;s instances can be a problem. |
| CLUSTER_RESOURCE_FFMPEG | 1 |  |
| CLUSTER_RESOURCE_IMAGEMAGICK | 2 |  |



<a name="rellm-NavigationTab"></a>

### NavigationTab
The default navigation tabs in Rellm&#39;s Elm UI.

| Name | Number | Description |
| ---- | ------ | ----------- |
| HOME_TAB | 0 | The home/landing tab. |
| EVENTS_TAB | 10 | The Events tab. |
| POSTS_TAB | 11 | The Posts tab. |
| PEOPLE_TAB | 12 | The People tab. |
| ABOUT_TAB | 15 | The About tab. |
| MARKET_TAB | 16 | The Market tab. |



<a name="rellm-NavigationTabStyle"></a>

### NavigationTabStyle
How a nav tab&#39;s icon and title are shown together, if at all. Applies uniformly to every tab
(`tabs` above, or the predefined `EVENTS_TAB`/`POSTS_TAB`/`PEOPLE_TAB`/`ABOUT_TAB` set when `tabs`
itself is unset) - there&#39;s no per-tab override.

| Name | Number | Description |
| ---- | ------ | ----------- |
| NAVIGATION_TAB_ICON_ONLY | 0 | Just the icon/emoji, no visible title (Rellm&#39;s original, still-default look). |
| NAVIGATION_TAB_TEXT_ONLY | 1 | Just the title text, no visible icon. |
| NAVIGATION_TAB_ICON_AND_TEXT_BELOW | 2 | Icon above, title below, stacked in one tab. |
| NAVIGATION_TAB_ICON_AND_TEXT_RIGHT | 3 | Icon and title side by side, icon first. |



<a name="rellm-PrivateUserStrategy"></a>

### PrivateUserStrategy
Strategy when a user sets their visibility to `PRIVATE`.

| Name | Number | Description |
| ---- | ------ | ----------- |
| ACCOUNT_IS_FROZEN | 0 | `PRIVATE` Users can&#39;t see other Users (only `PUBLIC_GLOBAL` Visilibity Users/Posts/Events). Other users can&#39;t see them. |
| LIMITED_CREEPINESS | 1 | Users can see other users they follow, but only `PUBLIC_GLOBAL` Visilibity Posts/Events. Other users can&#39;t see them. |
| LET_ME_CREEP_ON_PPL | 2 | Users can see other users they follow, including their `PUBLIC_SERVER` Posts/Events. Other users can&#39;t see them. |



<a name="rellm-VerificationAPI"></a>

### VerificationAPI


| Name | Number | Description |
| ---- | ------ | ----------- |
| VERIFICATION_API_TWILIO | 0 |  |
| VERIFICATION_API_BIRD | 1 |  |
| VERIFICATION_API_TELNYX | 2 |  |



<a name="rellm-WebUserInterface"></a>

### WebUserInterface
Offers a choice of web UIs. Generally though, React/Tamagui is
a century ahead of Flutter Web, so it&#39;s the default.

| Name | Number | Description |
| ---- | ------ | ----------- |
| FLUTTER_WEB | 0 | Uses Flutter Web. Loaded from /app. |
| HANDLEBARS_TEMPLATES | 1 | Uses Handlebars templates. Deprecated; will revert to Tamagui UI if chosen. |
| REACT_TAMAGUI | 2 | React UI using Tamagui (a React Native UI library). |
| ELM_SPA | 3 | Uses the Elm SPA client. Loaded from /elm. |


 

 

 



<a name="federation-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## federation.proto



<a name="rellm-FacebookAuthConfig"></a>

### FacebookAuthConfig
Facebook authentication configuration for the server.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| app_id | [string](#string) |  | The Facebook App ID for the server. |
| app_secret | [string](#string) |  | The Facebook App Secret for the server. *Never serialized to the client.* Admins: Edit this in the database&#39;s JSONB column directly. |






<a name="rellm-FederatedAccount"></a>

### FederatedAccount
Some user on a Rellm server.
Most commonly a different server than the one serving up FederatedAccount data,
but users may also federate multiple accounts on the same server.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| host | [string](#string) |  | The DNS hostname of the server that this user is on. |
| user_id | [string](#string) |  | The user ID of the user on the server. |






<a name="rellm-FederatedServer"></a>

### FederatedServer
A server that this server will federate with.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| host | [string](#string) |  | The DNS hostname of the server to federate with. |
| configured_by_default | [bool](#bool) | optional | Indicates to UI clients that they should enable/configure the indicated server by default. |
| pinned_by_default | [bool](#bool) | optional | Indicates to UI clients that they should pin the indicated server by default (showing its Events and Posts alongside the &#34;main&#34; server). |






<a name="rellm-FederationInfo"></a>

### FederationInfo
The federation configuration for a Rellm server.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| servers | [FederatedServer](#rellm-FederatedServer) | repeated | A list of servers that this server will federate with. |
| facebook_auth_config | [FacebookAuthConfig](#rellm-FacebookAuthConfig) | optional | Facebook authentication configuration for the server. If set, allows users to create Facebook (and Instagram) SyncDestinations for their Posts and Occasions. |
| x_twitter_auth_config | [XTwitterAuthConfig](#rellm-XTwitterAuthConfig) | optional | X (Twitter) authentication configuration for the server. If set, allows users to create X (Twitter) SyncDestinations for their Posts and Occasions - an admin registers one X Developer App here, and every user on the server connects their own X account through it via OAuth, the same relationship `facebook_auth_config` has to individual Facebook Pages. Until set, [`XTwitterAccount`](#rellm-XTwitterAccount) SyncDestinations always fail with `x_twitter_app_not_configured`. |
| mastodon_servers | [MastodonServer](#rellm-MastodonServer) | repeated | Mastodon instances this server has a registered OAuth app on, letting users connect/read their own account on that instance. Unlike Facebook/X, Mastodon has no single central platform to register an app against - every instance is its own separate OAuth authority, so an admin has to register an app on each instance individually before users on it can connect. If a user&#39;s instance isn&#39;t listed here, clients should surface a &#34;not configured&#34; alert rather than attempting to open an OAuth popup with no app to authorize against. (A client could instead dynamically self-register a throwaway app with the instance directly, via Mastodon&#39;s own `POST /api/v1/apps`, and skip this entirely - Mastodon itself supports that. But that&#39;s a client-side choice the Rellm protocol doesn&#39;t get involved in either way: this field only covers the admin-pre-registered path, which is what lets an app ID be shown/reused consistently across every client on this server rather than each one self-registering its own.) |






<a name="rellm-GetServiceVersionResponse"></a>

### GetServiceVersionResponse
Version information for the Rellm server.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| version | [string](#string) |  | The version of the Rellm server. May be suffixed with the GitHub SHA of the commit that generated the binary for the server. |






<a name="rellm-MastodonServer"></a>

### MastodonServer
A Mastodon instance this server has a registered OAuth app on. See `FederationInfo.mastodon_servers`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| domain | [string](#string) |  | The Mastodon instance&#39;s hostname, e.g. &#34;mastodon.social&#34;. |
| app_id | [string](#string) |  | The registered app&#39;s Client ID for this instance. Safe to serialize to clients - used directly to build the instance&#39;s `/oauth/authorize` URL, the same way `FacebookAuthConfig.app_id`/ `XTwitterAuthConfig.client_id` are. |
| app_secret | [string](#string) |  | The registered app&#39;s Client Secret for this instance. *Never serialized to the client.* Admins: Edit this in the database&#39;s JSONB column directly. Used server-side to exchange an authorization code for an access token once a user completes the OAuth popup. |
| configured_by_default | [bool](#bool) | optional | Indicates to UI clients that they should browse the indicated instance&#39;s public timeline by default (added to it with no OAuth/account needed at all - see this message&#39;s own doc on the difference between browsing and connecting). |
| pinned_by_default | [bool](#bool) | optional | Indicates to UI clients that they should pin the indicated instance by default (showing its Posts alongside the &#34;main&#34; server). Currently has the same effect as `configured_by_default` - as of this writing, clients have no &#34;added but not shown&#34; state for a browsed instance the way `FederatedServer.pinned_by_default`&#39;s `Server.enabled` does, so there&#39;s nothing for this to mean *in addition to* `configured_by_default`. Kept as its own field for symmetry with `FederatedServer`, and in case that changes. |






<a name="rellm-XTwitterAuthConfig"></a>

### XTwitterAuthConfig
X (Twitter) authentication configuration for the server. See `FederationInfo.x_twitter_auth_config`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| client_id | [string](#string) |  | The X Developer App&#39;s Client ID for the server. |
| client_secret | [string](#string) |  | The X Developer App&#39;s Client Secret for the server. *Never serialized to the client.* Admins: Edit this in the database&#39;s JSONB column directly. |





 

 

 

 



<a name="sync-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## sync.proto



<a name="rellm-BlueskyAccount"></a>

### BlueskyAccount
A Bluesky (AT Protocol) account connected as a [`SyncDestination`](#rellm-SyncDestination) via an &#34;App Password&#34;
(generated at Settings &gt; App Passwords - not the account&#39;s main password), rather than an
OAuth popup.

Media limitation: only attached *images* on a synced Post/Occasion are posted (up to 4,
downloaded and re-uploaded as Bluesky blobs) - video is silently dropped entirely. Bluesky
video embeds need a separate, more complex upload-and-processing flow not yet built.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| handle | [string](#string) |  | The account&#39;s handle, e.g. &#34;jon.bsky.social&#34;. |
| did | [string](#string) |  | The account&#39;s DID (decentralized identifier), populated by the server when the connection is made. |
| app_password | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination)/[`UpdateSyncDestination`](#grpc-api-UpdateSyncDestination): the user&#39;s own App Password. Never populated in responses. Sessions are created fresh per post rather than stored/refreshed, since App Passwords don&#39;t expire. |






<a name="rellm-DeleteSyncDestinationRequest"></a>

### DeleteSyncDestinationRequest
Request to delete a SyncDestination.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| destination | [SyncDestination](#rellm-SyncDestination) |  | The destination to be deleted. |
| delete_synced_posts | [bool](#bool) |  | Whether to also delete posts already made on the destination (e.g. the Facebook Page posts). |






<a name="rellm-DeleteSyncSourceRequest"></a>

### DeleteSyncSourceRequest
Request to delete a SyncSource.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source | [SyncSource](#rellm-SyncSource) |  | The source to be deleted. |
| delete_synced_events | [bool](#bool) |  | Whether to delete synced events. |






<a name="rellm-FacebookPage"></a>

### FacebookPage
A Facebook Page connected as a [`SyncDestination`](#rellm-SyncDestination) - **never a personal profile**. Facebook
deprecated the `publish_actions` permission in 2018, which was the only way any third-party app
could ever post to a personal timeline; there&#39;s no Graph API call today, for any app, that can
post anything (feed post, photo, or otherwise) to a personal profile on a user&#39;s behalf. A Page
is the only kind of Facebook entity a self-hosted server like this can post to at all - this
isn&#39;t a Rellm design choice to work around, it&#39;s a hard platform restriction. (Unrelated to
this: Facebook *Events* specifically are also unreachable, even for Pages - see
`docs/facebook_and_x_twitter_federation.md`&#39;s &#34;It posts to the Page&#39;s feed, not a real Facebook
Event&#34; for that separate, independent 2018-era lockdown.)

Media limitation: a synced Post/Occasion&#39;s attached video and images are mutually
exclusive on Facebook - if both are present, the video is posted and any images are silently
dropped (Facebook Pages can&#39;t attach both to a single feed post).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| page_id | [string](#string) |  | The Facebook Page&#39;s ID. |
| page_name | [string](#string) |  | The Facebook Page&#39;s name, populated by the server when the connection is made. |
| short_lived_user_access_token | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): a short-lived user access token from client-side Facebook Login, exchanged server-side for a long-lived Page access token. Never populated in responses. |






<a name="rellm-GetSyncDestinationsResponse"></a>

### GetSyncDestinationsResponse
Response to a request for the current user&#39;s [`SyncDestination`](#rellm-SyncDestination)s.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| destinations | [SyncDestination](#rellm-SyncDestination) | repeated | The current user&#39;s SyncDestinations. |






<a name="rellm-GetSyncSourcesResponse"></a>

### GetSyncSourcesResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| sources | [SyncSource](#rellm-SyncSource) | repeated |  |






<a name="rellm-InstagramAccount"></a>

### InstagramAccount
An Instagram Business/Creator account connected as a [`SyncDestination`](#rellm-SyncDestination) - **never a personal
Instagram account**. Unlike [`FacebookPage`](#rellm-FacebookPage)&#39;s restriction (a *deprecated* permission that used to let
apps post to a personal timeline), this one was never possible in the first place: Instagram&#39;s
Content Publishing API was built from the start only for professional (Business/Creator)
accounts, so a personal Instagram account simply has no API surface to post to at all,
regardless of what this server does. Posting to Instagram also requires the professional account
to be linked to a Facebook Page, so this reuses the same Facebook Login popup and app credentials
as [`FacebookPage`](#rellm-FacebookPage) - the server exchanges the token for the Page&#39;s access token, then looks up
that Page&#39;s linked Instagram Business account.

Media limitation: only the *first* attached image/video on a synced Post/Occasion is
posted - no carousel/multi-image support yet. A post with no media at all is rejected
(`instagram_requires_media`) - Instagram&#39;s Graph API has no text-only post type.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| instagram_business_account_id | [string](#string) |  | The Instagram Business/Creator account&#39;s ID, used for all Graph API posting calls. |
| username | [string](#string) |  | The Instagram account&#39;s @username, populated by the server when the connection is made. |
| page_id | [string](#string) |  | The linked Facebook Page&#39;s ID, kept for reference/reconnect. |
| short_lived_user_access_token | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): a short-lived user access token from client-side Facebook Login (same flow as [`FacebookPage`](#rellm-FacebookPage)), exchanged server-side for a long-lived Page access token, which is also used to post to the linked Instagram account. Never populated in responses. |






<a name="rellm-MastodonAccount"></a>

### MastodonAccount
A Mastodon account connected as a [`SyncDestination`](#rellm-SyncDestination) via a user-supplied Personal Access Token
(generated on the user&#39;s own instance, under Preferences &gt; Development), rather than an OAuth
popup - Mastodon instances are user-chosen arbitrary domains, so there&#39;s no single app to
register ahead of time the way Facebook/Instagram have one.

Media: up to 4 attached images/videos on a synced Post/Occasion are downloaded and
re-uploaded as real Mastodon media attachments (any mix of image/video types); a failed
individual upload is skipped rather than failing the whole post.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| instance_host | [string](#string) |  | The Mastodon instance&#39;s hostname, e.g. &#34;mastodon.social&#34;. |
| username | [string](#string) |  | The account&#39;s username on that instance, populated by the server when the connection is made. |
| access_token | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination)/[`UpdateSyncDestination`](#grpc-api-UpdateSyncDestination): the user&#39;s own Personal Access Token for `instance_host`. Never populated in responses. |






<a name="rellm-SyncDestination"></a>

### SyncDestination
A user-owned destination to sync (cross-post) content out to. Mirrors [`SyncSource`](#rellm-SyncSource),
but for pushing content out rather than pulling content in. Originally Event-specific
(as `EventSyncDestination`), now shared by both [`Occasion`](#rellm-Occasion)s (see `events.proto`&#39;s
[`SyncOccasionRequest`](#rellm-SyncOccasionRequest)) and [`Post`](#rellm-Post)s (see `posts.proto`&#39;s [`SyncPostRequest`](#rellm-SyncPostRequest)).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Unique ID for the destination. |
| owner | [Author](#rellm-Author) |  | The user information for the owner of this destination. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the SyncDestination was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the SyncDestination was last updated. |
| synced_occasion_count | [uint64](#uint64) | optional | The number of Occasions synced to this destination so far. Computed with a `COUNT` at request time (unlike [`SyncSource`](#rellm-SyncSource)&#39;s `event_count`/`occasion_count`, which are recomputed-and-stored on each sync) since destinations are pushed to on demand, not synced in bulk on an interval. |
| synced_post_count | [uint64](#uint64) | optional | The number of Posts synced to this destination so far. Computed the same way as `synced_occasion_count`, just against Posts instead of Occasions. |
| facebook_page | [FacebookPage](#rellm-FacebookPage) |  | A connected Facebook Page to post Occasions/Posts to. |
| instagram_account | [InstagramAccount](#rellm-InstagramAccount) |  | A connected Instagram Business/Creator account to post Occasions/Posts to. |
| mastodon_account | [MastodonAccount](#rellm-MastodonAccount) |  | A connected Mastodon account to post Occasions/Posts to. |
| bluesky_account | [BlueskyAccount](#rellm-BlueskyAccount) |  | A connected Bluesky account to post Occasions/Posts to. |
| x_twitter_account | [XTwitterAccount](#rellm-XTwitterAccount) |  | A connected X (Twitter) account to post Occasions/Posts to. |
| threads_account | [ThreadsAccount](#rellm-ThreadsAccount) |  | A connected Threads account to post Occasions/Posts to. |






<a name="rellm-SyncDestinationStatus"></a>

### SyncDestinationStatus
The status of a single piece of content&#39;s (an [`Occasion`](#rellm-Occasion) or [`Post`](#rellm-Post)) sync (cross-post) to
one [`SyncDestination`](#rellm-SyncDestination). Shared/generic so both `Occasion.sync_destinations` and
`Post.sync_destinations` can reuse it.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| sync_destination_id | [string](#string) |  | The SyncDestination this status is for. |
| destination_instance_id | [string](#string) | optional | The ID of the resulting post on the destination (e.g. a Facebook Post ID). |
| destination_url | [string](#string) | optional | A link to the resulting post on the destination, if available. |
| synced_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time this content was last successfully synced to the destination. |






<a name="rellm-SyncSource"></a>

### SyncSource
A user-owned source to sync events from.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Unique ID for the synchronization. |
| owner | [Author](#rellm-Author) |  | The user information for the owner of this sync source. |
| sync_interval_seconds | [uint64](#uint64) |  | How frequently the sync should happen in seconds. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the SyncSource was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the SyncSource was last updated. |
| last_synced_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the SyncSource was last synced. |
| event_count | [uint64](#uint64) |  | The number of events total associated with this SyncSource. Recomputed on each sync. |
| occasion_count | [uint64](#uint64) |  | The number of occasions total associated with this SyncSource. Recomputed on each sync. |
| post_count | [uint64](#uint64) |  | The number of posts total associated with this SyncSource. Populated for an RSS/Atom source (recomputed on each sync, like `event_count`/`occasion_count` are for an ICS source); always 0 for an ICS source, which syncs Events/Occasions instead. |
| ics_subscription_url | [string](#string) |  | The iCal subscription URL for the calendar sync. Creates/updates Events/Occasions. |
| rss_subscription_url | [string](#string) |  | The RSS subscription URL for the feed sync. Creates/updates plain Posts. |
| atom_subscription_url | [string](#string) |  | The Atom subscription URL for the feed sync. Creates/updates plain Posts. |






<a name="rellm-ThreadsAccount"></a>

### ThreadsAccount
A connected Threads account - **a genuinely personal account works fine here**, unlike
[`FacebookPage`](#rellm-FacebookPage)/[`InstagramAccount`](#rellm-InstagramAccount): the Threads API (a separate product from Instagram&#39;s,
launched 2024) has no Page-linkage or Business/Creator-account requirement at all - Threads
OAuth directly authorizes whatever single Threads account the user logs in with, personal or
not. It&#39;s still a product added to this server&#39;s existing Meta App (see [`FacebookAuthConfig`](#rellm-FacebookAuthConfig))
rather than a separately-registered app, so no separate auth config is needed. Unlike
[`FacebookPage`](#rellm-FacebookPage)/[`InstagramAccount`](#rellm-InstagramAccount), connecting one is a `response_type=code` OAuth flow at
threads.net (not facebook.com) with no &#34;choose a Page&#34; step - the code is exchanged server-side
for a short-lived token, then a long-lived one (~60 day expiry, refreshable via
`grant_type=th_refresh_token` - not yet implemented; a connected destination will need
reconnecting after ~60 days until a refresh job exists).

Media limitation: only the *first* attached image/video on a synced Post/Occasion is
posted - no carousel/multi-image support yet. Unlike [`InstagramAccount`](#rellm-InstagramAccount), a text-only post
(no media at all) is valid.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| threads_user_id | [string](#string) |  | The account&#39;s Threads user ID, used for all posting calls. |
| username | [string](#string) |  | The account&#39;s @username, populated by the server when the connection is made. |
| authorization_code | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the OAuth authorization code from the Threads login popup. Never populated in responses. |






<a name="rellm-XTwitterAccount"></a>

### XTwitterAccount
An X (Twitter) account connected as a [`SyncDestination`](#rellm-SyncDestination), via an OAuth 2.0 Authorization Code &#43;
PKCE flow at x.com. Requires this server to have a registered X Developer App configured (see
`FederationInfo.x_twitter_auth_config`) - every RPC touching an `XTwitterAccount` destination
fails with `x_twitter_app_not_configured` until an admin sets one, mirroring
[`FacebookAuthConfig`](#rellm-FacebookAuthConfig)/`facebook_app_not_configured`. Unlike Facebook/Instagram/Threads (which reuse one
Meta App), an admin registers this app once and every user on the server connects their own X
account through it - no per-user API keys needed.

Media limitation: up to 4 attached *images* on a synced Post/Occasion are downloaded and
re-uploaded via X&#39;s media upload endpoint. Video is not yet supported - X&#39;s video upload
requires a chunked upload-and-processing flow (mirroring Bluesky&#39;s own documented video gap)
not yet built; a video attachment is silently skipped.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| username | [string](#string) |  | The account&#39;s @username, populated by the server when the connection is made. |
| x_user_id | [string](#string) |  | The account&#39;s numeric X user ID, populated by the server when the connection is made. |
| authorization_code | [string](#string) | optional | Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the OAuth authorization code from the X login popup. Never populated in responses. |
| code_verifier | [string](#string) | optional | Only used (and required, alongside `authorization_code`) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the PKCE code verifier the popup generated before sending its paired `code_challenge` to X&#39;s authorize endpoint. X mandates PKCE (unlike Threads/Facebook&#39;s plain code exchange), so the server needs this to complete the token exchange. Never populated in responses. |





 

 

 

 



<a name="ai_providers-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## ai_providers.proto



<a name="rellm-AIModel"></a>

### AIModel
One specific model a user may call right now, and how - via an [`AIProvider`](#rellm-AIProvider)
they own outright (`grant` unset), or via an [`AIProviderGrant`](#rellm-AIProviderGrant) someone else
granted them (`grant` set). Only ever defined relative to a user - see
[`User.ai_models`](#rellm-User)/[`GetAIProvidersResponse.ai_models`](#rellm-GetAIProvidersResponse).
One `AIModel` exists per (provider, model) pair: an owner gets one row per model their
provider supports (see the server&#39;s own model catalog per provider type); a grantee gets one row
per model their grant actually covers - expanded from `AIProviderGrant.model_names`, or
every model the provider supports if that list is empty.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| model_name | [string](#string) |  | The exact model name to use when calling the provider (e.g. `&#34;gemini-3.1-flash-image&#34;`). |
| capabilities | [AIModelCapability](#rellm-AIModelCapability) | repeated | What this model can actually do - from the server&#39;s own hardcoded catalog for `provider.provider`&#39;s variant (see [`AIModelCapability`](#rellm-AIModelCapability)), not anything reported by the provider&#39;s API itself. Feature gating keys off this rather than `model_name` directly, so e.g. [`GenerateMedia`](#grpc-api-GenerateMedia) (which needs `AI_MODEL_CAPABILITY_IMAGE_EDITING` whenever `GenerateMediaRequest.media_ids` is non-empty, or just `AI_MODEL_CAPABILITY_IMAGE_GENERATION` when it&#39;s empty) doesn&#39;t need its own hardcoded list of model names. |
| grant | [AIProviderGrant](#rellm-AIProviderGrant) | optional | The grant that allows this access, when the current user isn&#39;t `provider.owner` themselves. Unset when the current user owns `provider` outright (full, ungated access - no grant needed). |
| provider | [AIProvider](#rellm-AIProvider) |  | The provider this model belongs to. Its own `grants` list is only populated when the current user is `provider.owner` (or an Admin) - see [`GetAIProviders`](#grpc-api-GetAIProviders)&#39;s own doc; a mere grantee never sees who else has been granted access to a provider they don&#39;t own. |






<a name="rellm-AIProvider"></a>

### AIProvider
An AIProvider is a user-owned connection to an external AI model API (e.g. a Gemini API
key), which its owner can grant other users of this server metered, budgeted access to. Mirrors
[`SyncDestination`](#rellm-SyncDestination)/[`SyncSource`](#rellm-SyncSource) (also user-owned integrations
with an [`Author`](#rellm-Author) `owner` and a `oneof` naming which external system is configured), but where
those push/pull content, an AIProvider is metered *access* to a third-party LLM API - shared out to
other users via [`AIProviderGrant`](#rellm-AIProviderGrant)s rather than posted-to/subscribed-from.

Providers are managed via [`GetAIProviders`](#grpc-api-GetAIProviders),
[`CreateAIProvider`](#grpc-api-CreateAIProvider) (requires `CREATE_AI_PROVIDERS`, or Admin),
[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) (owner, or Admin for any user&#39;s), and
[`DeleteAIProvider`](#grpc-api-DeleteAIProvider) (owner, or Admin) - the same self-or-Admin shape as
[`SyncDestination`](#rellm-SyncDestination)&#39;s RPCs. Access to a provider is granted/revoked to other users via
[`GrantAIProvider`](#grpc-api-GrantAIProvider)/[`RevokeAIProvider`](#grpc-api-RevokeAIProvider) which,
unlike every other RPC pair here, are **owner-only with no Admin override**: an Admin can manage the provider
record itself (rename it, rotate its key, delete it), but handing out access to *someone else&#39;s* API budget is a
call only its owner should be able to make.

[`GeminiCredentials`](#rellm-GeminiCredentials)/[`OpenAICredentials`](#rellm-OpenAICredentials)/
[`DigitalOceanCredentials`](#rellm-DigitalOceanCredentials) all have a working connection flow (Gemini&#39;s
Interactions API, OpenAI&#39;s Images API, DigitalOcean&#39;s Serverless Inference API - the last of which is also
OpenAI-Images-API-shaped, just a different base URL/key and generation-only, no editing endpoint);
[`AnthropicCredentials`](#rellm-AnthropicCredentials) is defined for forward compatibility but is not yet
accepted by [`CreateAIProvider`](#grpc-api-CreateAIProvider) (Anthropic doesn&#39;t offer image generation).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Unique ID for the AIProvider. |
| owner | [Author](#rellm-Author) |  | The user information for the owner of this AIProvider - the only user (besides Admins) who may rename it or change its credentials/provider, and the *only* user (not even Admins) who may grant/revoke other users&#39; access to it. |
| name | [string](#string) |  | A display name for the provider, chosen by its owner (e.g. &#34;My Gemini Key&#34;, &#34;Team OpenAI Account&#34;). Purely cosmetic - has no effect on behavior. |
| gemini_credentials | [GeminiCredentials](#rellm-GeminiCredentials) |  | A [Google Gemini API](https://ai.google.dev/gemini-api) connection, used for image generation/editing (e.g. generating Event posters) via its [Interactions API](https://ai.google.dev/gemini-api/docs/image-generation). |
| openai_credentials | [OpenAICredentials](#rellm-OpenAICredentials) |  | An [OpenAI API](https://platform.openai.com/docs/api-reference) connection, used for image generation/editing via its [Images API](https://platform.openai.com/docs/guides/image-generation) (GPT Image models). |
| anthropic_credentials | [AnthropicCredentials](#rellm-AnthropicCredentials) |  | An [Anthropic API](https://docs.anthropic.com) connection. *Not yet creatable* - Anthropic doesn&#39;t offer an image generation API. |
| digitalocean_credentials | [DigitalOceanCredentials](#rellm-DigitalOceanCredentials) |  | A [DigitalOcean Gradient AI Platform](https://docs.digitalocean.com/products/gradient-ai-platform/) / Serverless Inference connection, used for image generation (no editing - DigitalOcean&#39;s [Serverless Inference API](https://docs.digitalocean.com/products/gradient-ai-platform/reference/api/serverless-inference/) has no `/v1/images/edits`-equivalent endpoint) via its OpenAI-Images-API-shaped `/v1/images/generations` endpoint (GPT Image and Stable Diffusion models, re-hosted under DigitalOcean&#39;s own billing). |
| grants | [AIProviderGrant](#rellm-AIProviderGrant) | repeated | Other users this provider&#39;s owner has granted metered access to, via [`GrantAIProvider`](#grpc-api-GrantAIProvider). Only ever populated for the owner (or an Admin) -- see [`GetAIProviders`](#grpc-api-GetAIProviders). |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the provider was created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the provider was last updated (renamed, or had its provider/credentials changed). |






<a name="rellm-AIProviderGrant"></a>

### AIProviderGrant
A grant of metered access to someone else&#39;s [`AIProvider`](#rellm-AIProvider), created/reset via
[`GrantAIProvider`](#grpc-api-GrantAIProvider) and removed via
[`RevokeAIProvider`](#grpc-api-RevokeAIProvider). Upserted on the unique
`(ai_provider_id, ai_model_grantee)` pair - calling [`GrantAIProvider`](#grpc-api-GrantAIProvider)
again for a user who already has a grant *resets* `tokens_remaining` to the newly-requested amount, it does not
add to it.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ai_provider_id | [string](#string) |  | The ID of the [`AIProvider`](#rellm-AIProvider) this grant is for. |
| ai_model_grantee | [Author](#rellm-Author) |  | The user this access was granted to. |
| model_names | [string](#string) | repeated | The model name (that will be used to call the provider) that the grantee is allowed to use by this grant. If blank, allows access to any models the provider supports. If non-blank, the grantee is only allowed to use the model(s) specified here. Allows granters to set per-model (or per-model-group) token budgets, e.g. &#34;gpt-4&#34; vs &#34;gpt-3.5-turbo&#34;. |
| tokens_remaining | [uint64](#uint64) |  | The number of tokens the grantee may still spend against this provider. Set (and reset) by the owner via [`GrantAIProvider`](#grpc-api-GrantAIProvider). Once this reaches 0, [`GenerateMedia`](#grpc-api-GenerateMedia) stops working for the grantee entirely, until the owner grants more via [`GrantAIProvider`](#grpc-api-GrantAIProvider) again. |
| overage | [uint64](#uint64) |  | How far a single [`GenerateMedia`](#grpc-api-GenerateMedia) call&#39;s actual token usage overshot `tokens_remaining` the moment it hit 0 - effectively a &#34;negative `tokens_remaining`&#34; (which, being `uint64`, can&#39;t represent a negative value directly), recorded here instead as a positive debt for the owner&#39;s own visibility. E.g. a grantee with 30 tokens left whose next call actually costs 45 ends up with `tokens_remaining = 0` and `overage = 15`. Always 0 immediately after a fresh [`GrantAIProvider`](#grpc-api-GrantAIProvider) call (any prior debt is cleared, not carried forward) - see that RPC&#39;s own doc. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | The time the grant was first created. |
| updated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time the grant was last updated (i.e. last reset by another [`GrantAIProvider`](#grpc-api-GrantAIProvider) call). |






<a name="rellm-AnthropicCredentials"></a>

### AnthropicCredentials
Credentials for an [Anthropic API](https://docs.anthropic.com) connection. *Not yet creatable* - defined for
forward compatibility only.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| anthropic_api_key | [string](#string) | optional | The Anthropic API key. Never populated in responses (see [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)). |






<a name="rellm-DeleteAIProviderRequest"></a>

### DeleteAIProviderRequest
Request to delete an AIProvider. Also deletes any of its [`AIProviderGrant`](#rellm-AIProviderGrant)s.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| provider | [AIProvider](#rellm-AIProvider) |  | The provider to be deleted. |






<a name="rellm-DigitalOceanCredentials"></a>

### DigitalOceanCredentials
Credentials for a [DigitalOcean Gradient AI Platform](https://docs.digitalocean.com/products/gradient-ai-platform/) /
Serverless Inference connection, accepted by
[`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
Used for image *generation only* (no editing - see `AIProvider.provider`&#39;s own doc on this variant) via its
[Serverless Inference API](https://docs.digitalocean.com/products/gradient-ai-platform/reference/api/serverless-inference/)
`/v1/images/generations` endpoint, OpenAI-Images-API-shaped and re-hosting GPT Image and Stable Diffusion models --
see [`GenerateMedia`](#grpc-api-GenerateMedia).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| digitalocean_api_key | [string](#string) | optional | The DigitalOcean Serverless Inference API token. Required (and only used) on [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) -- never populated in responses (see [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)). |






<a name="rellm-GeminiCredentials"></a>

### GeminiCredentials
Credentials for a [Google Gemini API](https://ai.google.dev/gemini-api) connection - the only
[`AIProvider.provider`](#rellm-AIProvider) variant currently accepted by
[`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
Used for image generation/editing via Gemini&#39;s [Interactions API](https://ai.google.dev/gemini-api/docs/image-generation),
e.g. to generate/edit Event posters from an Event&#39;s own content - see [`GenerateMedia`](#grpc-api-GenerateMedia).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| gemini_api_key | [string](#string) | optional | The Gemini API key. Required (and only used) on [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) -- **never populated in responses**, the same write-only convention as e.g. [`MastodonAccount.access_token`](#rellm-MastodonAccount) in `sync.proto`. |






<a name="rellm-GenerateMediaRequest"></a>

### GenerateMediaRequest
Request to generate (or edit) an image via one of the current user&#39;s
[`AIModel`](#rellm-AIModel)s - see [`GenerateMedia`](#grpc-api-GenerateMedia). The resulting
image is stored as a new [`Media`](#rellm-Media) (`generated = true`) owned by the current user, and - if
`target` is set - prepended as the *first* item in that Post&#39;s (or Event&#39;s own Post&#39;s) `media` list.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| model | [AIModel](#rellm-AIModel) |  | Which of the current user&#39;s `AIModel`s to generate with - `model.model_name` selects the actual model, `model.provider.id` identifies whose `AIProvider` (the current user&#39;s own, or one they&#39;ve been granted access to) to call it through. Only `model_name`/`provider.id` are read server-side - any other field sent here (e.g. a spoofed `grant`) is ignored in favor of the caller&#39;s real access, re-derived from `provider.id` and the current user. |
| user_prompt | [string](#string) |  | The user-editable prompt describing what to generate, e.g. &#34;Please generate a square headline poster for the following event.&#34; Combined server-side with `target`&#39;s own formatted content (title/description/date-time range/location - the same formatting [`SyncDestination`](#rellm-SyncDestination)s use) before being sent to the model, so the user never has to paste that context in by hand. |
| media_ids | [string](#string) | repeated | Existing [`Media`](#rellm-Media) to pass to the model alongside `user_prompt`, for image editing/ reference-based generation (e.g. a target Post/Event&#39;s own current photos), in the order given here. Leave empty for plain text-to-image generation instead - `model` must have the matching capability either way (`AI_MODEL_CAPABILITY_IMAGE_EDITING` here, `AI_MODEL_CAPABILITY_IMAGE_GENERATION` if empty - see [`AIModelCapability`](#rellm-AIModelCapability)&#39;s own doc). Every id must be owned by the current user (or the current user must be an Admin). |
| post_id | [string](#string) |  | Attach to (and use the content of) this Post. Caller must be its author, or an Admin. |
| occasion_id | [string](#string) |  | Attach to (and use the content of) this Occasion&#39;s parent Event&#39;s own Post - named by Occasion, not Event, since that&#39;s what a viewer is actually looking at (and what gives the generated prompt its date/time/location context, the same way [`SyncOccasion`](#grpc-api-SyncOccasion) does). Caller must be the Event&#39;s own Post&#39;s author, or hold `MODERATE_POSTS`/`MODERATE_EVENTS`, or be an Admin. |






<a name="rellm-GetAIProvidersResponse"></a>

### GetAIProvidersResponse
Response to a request for a user&#39;s [`AIProvider`](#rellm-AIProvider)s.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| providers | [AIProvider](#rellm-AIProvider) | repeated | The requested user&#39;s own AIProviders (those they own) - exactly the distinct `provider`s in `ai_models` whose `owner` is the requested user, each with its own `grants` populated (who else can use it). A convenience duplicate of data already in `ai_models`, so callers managing a user&#39;s own providers (rename/rekey/delete/grant/ revoke) don&#39;t have to de-duplicate that list themselves. |
| ai_models | [AIModel](#rellm-AIModel) | repeated | Every model the requested user may currently call - their own providers&#39; models, plus any models granted to them on other users&#39; providers. See [`AIModel`](#rellm-AIModel)&#39;s own doc. |






<a name="rellm-GrantAIProviderRequest"></a>

### GrantAIProviderRequest
Request to grant (or reset) another user&#39;s metered access to one of the current user&#39;s
[`AIProvider`](#rellm-AIProvider)s. *Authenticated, owner-only - no Admin override.*


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The user to grant access to. |
| ai_provider_id | [string](#string) |  | The AIProvider to grant access to. Must be owned by the caller. |
| tokens | [uint64](#uint64) |  | The number of tokens the grantee may spend. Calling this RPC again for the same (`ai_provider_id`, `user_id`) pair *replaces*, rather than adds to, this value. |
| model_names | [string](#string) | repeated | The models the grantee is allowed to use, mirroring [`AIProviderGrant.model_names`](#rellm-AIProviderGrant) - if empty, allows access to any model the provider supports. Also replaced (not merged) on a repeat call, same as `tokens`. |






<a name="rellm-OpenAICredentials"></a>

### OpenAICredentials
Credentials for an [OpenAI API](https://platform.openai.com/docs/api-reference) connection, accepted by
[`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
Used for image generation/editing via OpenAI&#39;s [Images API](https://platform.openai.com/docs/guides/image-generation)
(the GPT Image model family) - same use case as [`GeminiCredentials`](#rellm-GeminiCredentials), see
[`GenerateMedia`](#grpc-api-GenerateMedia).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| openai_api_key | [string](#string) | optional | The OpenAI API key. Required (and only used) on [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) -- never populated in responses (see [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)). |






<a name="rellm-RevokeAIProviderRequest"></a>

### RevokeAIProviderRequest
Request to revoke another user&#39;s access to one of the current user&#39;s
[`AIProvider`](#rellm-AIProvider)s, the reverse of
[`GrantAIProvider`](#grpc-api-GrantAIProvider). *Authenticated, owner-only - no Admin override.*


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | The user whose access should be revoked. |
| ai_provider_id | [string](#string) |  | The AIProvider to revoke access to. Must be owned by the caller. |





 


<a name="rellm-AIModelCapability"></a>

### AIModelCapability
What an [`AIModel`](#rellm-AIModel) can actually do - drives feature gating
(e.g. [`GenerateMedia`](#grpc-api-GenerateMedia)&#39;s &#34;Generate Media…&#34; buttons/panel only offer
models carrying `AI_MODEL_CAPABILITY_IMAGE_EDITING`/`AI_MODEL_CAPABILITY_IMAGE_GENERATION`)
without the gated feature needing its own hardcoded list of model names to check against. A
model may carry more than one - e.g. an image-editing model can also usually do plain
text-to-image generation.

| Name | Number | Description |
| ---- | ------ | ----------- |
| AI_MODEL_CAPABILITY_UNKNOWN | 0 | The model&#39;s capabilities are unknown (e.g. the server doesn&#39;t know what this provider supports). |
| AI_MODEL_CAPABILITY_TEXT_GENERATION | 1 | The model can generate new text from a prompt. |
| AI_MODEL_CAPABILITY_IMAGE_GENERATION | 2 | The model can generate a new image from a text prompt alone - what [`GenerateMedia`](#grpc-api-GenerateMedia) requires when `GenerateMediaRequest.media_ids` is empty (no reference images to edit with). |
| AI_MODEL_CAPABILITY_IMAGE_EDITING | 3 | The model can edit an existing image, given a text prompt and one or more reference images -- what [`GenerateMedia`](#grpc-api-GenerateMedia) requires instead, whenever `GenerateMediaRequest.media_ids` is non-empty. Not every model with `AI_MODEL_CAPABILITY_IMAGE_GENERATION` also has this - some (e.g. the cheaper/faster `gemini-3.1-flash-lite-image` tier) only support plain generation. |


 

 

 



<a name="market-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## market.proto



<a name="rellm-AIGrantPurchaseDetails"></a>

### AIGrantPurchaseDetails
`MarketPurchase.details`&#39; `PURCHASE_TYPE_AI_GRANTS` variant -- copied verbatim from the
originating `MarketProduct.details` at the moment this purchase was fulfilled. Field-for-field
identical to `AIGrantSubscriptionDetails` -- see `MediaStoragePurchaseDetails`&#39;s own doc for why
it&#39;s still a separate message.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ai_provider_id | [string](#string) |  | Which `AIProvider` this grant is against. |
| model_names | [string](#string) | repeated | Which of that provider&#39;s models the grant covers. |
| tokens | [uint64](#uint64) |  | The buyer&#39;s new total token balance for `ai_provider_id`/`model_names`, replacing (not adding to) whatever balance remained -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `AiGrants` arm. |






<a name="rellm-AIGrantSubscriptionDetails"></a>

### AIGrantSubscriptionDetails
`MarketProduct.details`/`MarketSubscription.details`&#39; `PURCHASE_TYPE_AI_GRANTS` variant -- what
an AI token product actually grants. Field-for-field identical to `AIGrantPurchaseDetails` --
see that message&#39;s own doc for why it&#39;s still a distinct type.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ai_provider_id | [string](#string) |  | Which `AIProvider` this grant is against. |
| model_names | [string](#string) | repeated | Which of that provider&#39;s models the grant covers. |
| tokens | [uint64](#uint64) |  | How many tokens this product/subscription grants the buyer each time it&#39;s (re-)fulfilled, replacing (not adding to) whatever balance remained -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `AiGrants` arm. |






<a name="rellm-FulfillmentNote"></a>

### FulfillmentNote
One entry in a MarketSubscription&#39;s `fulfillment_notes` -- see that field&#39;s own doc. Immutable
once appended: `UpdateMarketSubscription` only ever accepts a `fulfillment_notes` list whose
existing entries are byte-for-byte identical to what&#39;s already stored (see that RPC&#39;s own doc).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| user_id | [string](#string) |  | Whoever wrote this note -- either the fulfilling admin or the buyer themselves, depending on which side of the conversation this entry is. Must match the id of whoever&#39;s actually making the `UpdateMarketSubscription` request that appends this entry (server-validated -- see that RPC&#39;s own doc); a client can&#39;t author a note on someone else&#39;s behalf. |
| note | [string](#string) |  | The note&#39;s own text -- required (rejected with `fulfillment_note_text_required`) unless this entry also changes `fulfillment_status` from whatever the previous entry (or, for the very first note, the implicit `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` default) left it at, in which case an admin can record a bare status change with no accompanying text (e.g. the automatic &#34;admin opened this order&#34; transition to `FULFILLMENT_STATUS_IN_PROGRESS` -- see that enum value&#39;s own doc). |
| fulfillment_status | [FulfillmentStatus](#rellm-FulfillmentStatus) |  | What `RellmHostingSubscriptionDetails.fulfillment_status` became as of this note -- unchanged from the previous entry for a plain note, or the new value for an actual status transition (see `note`&#39;s own doc on when text is/isn&#39;t required for each case). This is what makes `fulfillment_notes` a genuine &#34;fulfillment state history,&#34; not just a chat log alongside a separately-tracked current status. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this note was added. Server-stamped -- `UpdateMarketSubscription` always ignores whatever timestamp the client sends for a newly-appended entry. |






<a name="rellm-GetMarketProductsRequest"></a>

### GetMarketProductsRequest
Request to get products available for purchase on a Rellm server. *Unauthenticated* --
`GetMarketProducts` never requires a signed-in caller (see that RPC&#39;s own doc), so anyone can
browse a server&#39;s Market without an account, including from another federated server (see
`rellm.proto`&#39;s &#34;Federated Markets&#34; doc). For now, there are few enough products per server that
this has no filtering/paging parameters.






<a name="rellm-GetMarketProductsResponse"></a>

### GetMarketProductsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| market_products | [MarketProduct](#rellm-MarketProduct) | repeated | Every non-delisted `MarketProduct`, plus delisted ones too if the caller is a signed-in admin on this server (so admins can still find/relist/edit a delisted product from the same `/market` page everyone else sees). |






<a name="rellm-GetMarketSubscriptionsRequest"></a>

### GetMarketSubscriptionsRequest
Request to get MarketSubscriptions -- self-scoped to the current user&#39;s own
(`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE`, the default -- there&#39;s no way to fetch another
user&#39;s own subscriptions this way, even as an admin), or -- for an admin only --
`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`, every `PURCHASE_TYPE_RELLM_HOSTING`
subscription across every buyer, for the `/market/fulfillment` admin page.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_type | [GetMarketSubscriptionsRequestType](#rellm-GetMarketSubscriptionsRequestType) |  | Which of the two views below to return. Defaults to `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE` (proto3&#39;s implicit `0` default), so existing callers that predate this field keep getting their own subscriptions, not the admin view. |






<a name="rellm-GetMarketSubscriptionsResponse"></a>

### GetMarketSubscriptionsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| market_subscriptions | [MarketSubscription](#rellm-MarketSubscription) | repeated | For `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE`: the caller&#39;s own subscriptions, newest first. For `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`: every `PURCHASE_TYPE_RELLM_HOSTING` subscription across every buyer, oldest first (so the oldest unfulfilled order surfaces at the top of `/market/fulfillment`). |






<a name="rellm-MakeMarketPurchaseRequest"></a>

### MakeMarketPurchaseRequest
Authenticated*. Buys `market_product_id` for the current user, starting (or continuing) a
Stripe Checkout flow -- see `MakeMarketPurchaseResponse.checkout_url`. No `MarketPurchase`/
`MarketSubscription` is created by this call itself; that only happens once Stripe confirms
payment via webhook, so an abandoned checkout never leaves a half-created purchase behind.
Rejected outright (`market_disabled`) if `market_settings.enabled` is false -- checked first,
ahead of every product-specific precondition (delisted/sold-out/Stripe-not-configured/etc.),
since an admin who&#39;s closed Market entirely shouldn&#39;t have that bypassable by simply knowing a
still-valid product id.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| market_product_id | [string](#string) |  |  |
| rellm_hosting_details | [RellmHostingPurchaseDetails](#rellm-RellmHostingPurchaseDetails) | optional | Only meaningful (and required) for a `PURCHASE_TYPE_RELLM_HOSTING` product -- the buyer&#39;s desired domain/contact info/notes, carried through to Stripe as Checkout Session metadata and copied onto the resulting `MarketPurchase`/`MarketSubscription` once payment completes. |






<a name="rellm-MakeMarketPurchaseResponse"></a>

### MakeMarketPurchaseResponse
A pending Stripe Checkout Session, ready to redirect the buyer&#39;s browser to.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| checkout_url | [string](#string) |  | Redirect the buyer&#39;s browser here (a Stripe-hosted Checkout page) to complete payment. Expires after Stripe&#39;s own Checkout Session timeout if never completed -- since no `MarketPurchase` row is created until the webhook fires (see this message&#39;s own request&#39;s doc), an abandoned/expired checkout leaves no trace at all. |






<a name="rellm-MarketPayment"></a>

### MarketPayment
A single successful charge against a `MarketPurchase` -- one row per completed Stripe
`PaymentIntent` (the initial purchase&#39;s, or a later renewal&#39;s). Backed by the same
`market_payments` table as `MarketRefund` (a positive `amount` row marshals to a `MarketPayment`,
a negative one to a `MarketRefund` -- see that message&#39;s own doc), so a `MarketPayment` is never
itself edited or deleted once created; a refund is always its own separate row/message.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| amount | [uint32](#uint32) |  | The amount actually charged, in the same unit `MarketProduct.amount` uses (smallest unit of `currency`, except for a zero-decimal currency like JPY). |
| currency | [uint32](#uint32) |  | The ISO 4217 numeric currency code `amount` is denominated in -- copied from the purchase&#39;s own product at charge time. |
| market_purchase_id | [string](#string) |  |  |
| method | [MarketPaymentMethod](#rellm-MarketPaymentMethod) | optional | The card actually charged, if known/resolvable at the time this MarketPayment was recorded. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this charge succeeded. |






<a name="rellm-MarketPaymentMethod"></a>

### MarketPaymentMethod
Card details for a MarketPayment, resolved from Stripe at charge time (Stripe&#39;s own
`PaymentMethod.card` object). Unset entirely if the payment wasn&#39;t card-based or details
couldn&#39;t be resolved. Never carries anything more sensitive than what Stripe itself considers
safe to display (brand/last4/expiry) -- never a full card number.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| card_brand | [string](#string) |  | E.g. &#34;visa&#34;, &#34;mastercard&#34;, &#34;amex&#34;. |
| card_last4 | [string](#string) |  | Last 4 digits of the card number. |
| card_exp_month | [uint32](#uint32) |  | 1-12. |
| card_exp_year | [uint32](#uint32) |  | 4-digit year. |






<a name="rellm-MarketProduct"></a>

### MarketProduct
An actual subscribable product listed on, say, https://rellm.org/market -- what an admin creates
via `CreateMarketProduct`/edits via `UpdateMarketProduct`, and what a buyer actually purchases via
`MakeMarketPurchase`. `market_settings.enabled` (see `server_configuration.proto`) gates whether a
server&#39;s Market is browsable/purchasable at all, independent of any individual product&#39;s own
`delisted_at`. Listed/delisted by clients by setting `delisted_at` (though the actual date
supplied by the client is ignored -- see that field&#39;s own doc).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| type | [PurchaseType](#rellm-PurchaseType) |  | What this product grants once purchased -- see `PurchaseType`&#39;s own doc for what each value does. Never changeable after product creation (`UpdateMarketProduct` silently ignores any change to this field) -- changing what a product *is* after people have already bought it would silently change existing buyers&#39; entitlements out from under them; a product whose type needs to change is delisted and replaced with a new one instead. |
| period | [PurchasePeriod](#rellm-PurchasePeriod) |  | How often this product bills, if at all -- see `PurchasePeriod`&#39;s own doc. Never changeable after product creation, same reasoning as `type` above. |
| amount | [uint32](#uint32) |  | The price, in the smallest unit of `currency` (e.g. cents for USD) -- except for a zero-decimal currency like JPY, where this is already the whole unit (see `logic::stripe_sync::is_zero_decimal_currency`). |
| currency | [uint32](#uint32) |  | The ISO 4217 numeric currency code this product is priced in (e.g. `840` for USD, `392` for JPY) -- see `logic::market_summary`&#39;s currency table for the full set of currencies a server actually supports pricing in today. |
| available_count | [uint32](#uint32) |  | Number of subscription &#34;slots&#34; available for this product (admin-set) -- `0` means unlimited. Once `sold_count &gt;= available_count` (and `available_count &gt; 0`), `MakeMarketPurchase` rejects further purchases with `product_sold_out`. |
| sold_count | [uint32](#uint32) |  | Number of subscriptions actually sold, maintained server-side (never client-settable -- `UpdateMarketProduct` silently ignores any client-sent value for this field). Incremented when a purchase&#39;s Stripe Checkout Session completes; decremented when the resulting `MarketSubscription` is actually canceled (`CancelMarketSubscription`), freeing the slot for a new buyer. |
| media_storage_subscription_details | [MediaStorageSubscriptionDetails](#rellm-MediaStorageSubscriptionDetails) |  |  |
| ai_grant_subscription_details | [AIGrantSubscriptionDetails](#rellm-AIGrantSubscriptionDetails) |  |  |
| rellm_hosting_subscription_details | [RellmHostingSubscriptionDetails](#rellm-RellmHostingSubscriptionDetails) |  |  |
| permissions_access_subscription_details | [PermissionsAccessSubscriptionDetails](#rellm-PermissionsAccessSubscriptionDetails) |  |  |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this product was created. Server-stamped -- `CreateMarketProduct` ignores any client-sent value. |
| delisted_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | If set, the MarketProduct is not purchasable -- still shown to admins (see `GetMarketProductsResponse.market_products`&#39; own doc), but hidden from every other caller and rejected by `MakeMarketPurchase`. Note: clients toggle listings by setting this, but the server will always set it to the time of the request, not the time sent *by* the request. |






<a name="rellm-MarketPurchase"></a>

### MarketPurchase
One completed billing event -- the initial purchase or a later recurring renewal charge -- for a
single product. Created only from `web::stripe_webhook` (the initial purchase, on
`checkout.session.completed`) or `logic::market_renewal` (each subsequent recurring charge),
never directly by `MakeMarketPurchase` itself (see that RPC&#39;s own doc). MarketPurchases are
immutable via the API&#43;CLI once created -- there is no `UpdateMarketPurchase` RPC; the payments,
refunds, and (for a subscription) fulfillment information that accumulate against a purchase over
time live in their own separate messages/tables instead of ever rewriting this one.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| buyer | [Author](#rellm-Author) |  | Who bought this. |
| type | [PurchaseType](#rellm-PurchaseType) |  | What this purchase grants -- copied from (and always matching) `market_product.type` at the time of purchase. Denormalized here (rather than requiring a lookup through `market_product`) so a client can branch on `details`&#39; oneof case without needing `market_product` populated. |
| market_product | [MarketProduct](#rellm-MarketProduct) |  | The `MarketProduct` this purchase was made against, as it existed at the time it was fetched -- may since have changed price/details/been delisted; this purchase&#39;s own `amount`-equivalent fields live on whichever `MarketPayment`s are attached, not here. |
| market_subscription | [MarketSubscription](#rellm-MarketSubscription) | optional | The subscription this purchase belongs to -- every purchase gets one, including a `PURCHASE_PERIOD_INDEFINITE` one-time purchase (see `MarketSubscription`&#39;s own doc), so `Optional` here really only means &#34;always unset when this `MarketPurchase` is itself embedded inside a `MarketSubscription.billing_history`&#34; (there&#39;d be no point recursing into the same subscription again). Note: this circular relationship should be handled by the Rust marshaling side. |
| market_payments | [MarketPayment](#rellm-MarketPayment) | repeated | Every payment recorded against this purchase, oldest first -- ordinarily just one, but a failed charge that&#39;s later retried (see `logic::market_renewal`) can leave more than one row. |
| market_refunds | [MarketRefund](#rellm-MarketRefund) | repeated | Every refund recorded against this purchase, oldest first -- empty for the common case of a purchase that was never refunded. |
| media_storage_purchase_details | [MediaStoragePurchaseDetails](#rellm-MediaStoragePurchaseDetails) |  |  |
| ai_grant_purchase_details | [AIGrantPurchaseDetails](#rellm-AIGrantPurchaseDetails) |  |  |
| rellm_hosting_purchase_details | [RellmHostingPurchaseDetails](#rellm-RellmHostingPurchaseDetails) |  |  |
| permissions_access_purchase_details | [PermissionsAccessPurchaseDetails](#rellm-PermissionsAccessPurchaseDetails) |  |  |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this purchase was recorded -- i.e. when the Stripe webhook/renewal job actually processed it, not when the buyer started checkout. |






<a name="rellm-MarketRefund"></a>

### MarketRefund
A single refund issued against a `MarketPurchase`&#39;s payment -- see `MarketPayment`&#39;s own doc for
how this and `MarketPayment` share the same underlying `market_payments` table.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| amount | [uint32](#uint32) |  | The amount refunded, in the same unit the original `MarketPayment.amount` was charged in -- always positive here (the underlying row&#39;s negative `amount` is what distinguishes a refund from a payment; this message itself never exposes the sign). |
| currency | [uint32](#uint32) |  | The ISO 4217 numeric currency code `amount` is denominated in -- always matches the `MarketPayment.currency` being refunded. |
| market_purchase_id | [string](#string) |  |  |
| method | [MarketRefundMethod](#rellm-MarketRefundMethod) | optional | The card the refund was issued back to -- in practice always the same card as the MarketPayment being refunded, since Stripe refunds are only ever issued back to their original payment method. |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this refund was issued. |






<a name="rellm-MarketRefundMethod"></a>

### MarketRefundMethod
Same shape as MarketPaymentMethod -- kept as its own message (rather than reusing
MarketPaymentMethod directly) since a MarketRefund and the MarketPayment it refunds are
otherwise-independent messages, matching the MarketPayment/MarketRefund split itself.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| card_brand | [string](#string) |  | E.g. &#34;visa&#34;, &#34;mastercard&#34;, &#34;amex&#34;. |
| card_last4 | [string](#string) |  | Last 4 digits of the card number. |
| card_exp_month | [uint32](#uint32) |  | 1-12. |
| card_exp_year | [uint32](#uint32) |  | 4-digit year. |






<a name="rellm-MarketSubscription"></a>

### MarketSubscription
Created for *every* `MarketPurchase`, regardless of `MarketProduct.period` -- a recurring
(`PURCHASE_PERIOD_ANNUAL`/`PURCHASE_PERIOD_MONTHLY`) one gets re-billed and re-fulfilled
automatically every period by `renew_market_subscriptions.rs` until canceled; a
`PURCHASE_PERIOD_INDEFINITE` one-time purchase gets a subscription too (with `renews_at` unset --
see that field&#39;s own doc), purely so it&#39;s still cancelable and still carries the same per-type
fulfillment tracking (e.g. `RellmHostingSubscriptionDetails.fulfillment_status`/`fulfillment_notes`) every
other purchase type gets, even though it never actually bills again.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| buyer | [Author](#rellm-Author) |  | Who owns this subscription (i.e. who&#39;s being billed and who the entitlement applies to). |
| type | [PurchaseType](#rellm-PurchaseType) |  | What this subscription grants -- copied from (and always matching) `market_product.type`. Denormalized here the same way `MarketPurchase.type` is -- see that field&#39;s own doc. |
| period | [PurchasePeriod](#rellm-PurchasePeriod) |  | How often this subscription bills -- copied from `market_product.period` at the time this subscription was created. `PURCHASE_PERIOD_INDEFINITE` is valid here too (see this message&#39;s own doc) -- it just means `renews_at` stays unset and this subscription never actually bills again. |
| amount | [uint32](#uint32) |  | The price charged each renewal, in the same unit `MarketProduct.amount` uses -- copied from `market_product.amount` at the time this subscription was created, so a later price change to the product doesn&#39;t retroactively re-price an existing subscriber. |
| currency | [uint32](#uint32) |  | The ISO 4217 numeric currency code `amount` is denominated in -- copied from `market_product.currency` at the time this subscription was created. |
| market_product | [MarketProduct](#rellm-MarketProduct) |  | The `MarketProduct` this subscription was made against, as it existed at the time it was fetched -- may since have changed price/details/been delisted (delisting an already-subscribed product doesn&#39;t cancel existing subscriptions, only blocks new purchases). Note: marshaling should handle the circular relationship here gracefully. |
| billing_history | [MarketPurchase](#rellm-MarketPurchase) | repeated | Every `MarketPurchase` billed against this subscription so far -- the original purchase plus every successful renewal charge, newest first. Each entry&#39;s own `market_subscription` field is left unset here (see `MarketPurchase.market_subscription`&#39;s own doc) to avoid recursing back into this same subscription. |
| media_storage_subscription_details | [MediaStorageSubscriptionDetails](#rellm-MediaStorageSubscriptionDetails) |  |  |
| ai_grant_subscription_details | [AIGrantSubscriptionDetails](#rellm-AIGrantSubscriptionDetails) |  |  |
| rellm_hosting_subscription_details | [RellmHostingSubscriptionDetails](#rellm-RellmHostingSubscriptionDetails) |  |  |
| permissions_access_subscription_details | [PermissionsAccessSubscriptionDetails](#rellm-PermissionsAccessSubscriptionDetails) |  |  |
| created_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  | When this subscription was first created (i.e. when the initial `MarketPurchase` was fulfilled). |
| renews_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | When the next renewal charge is due. Always unset for a `PURCHASE_PERIOD_INDEFINITE` subscription (see this message&#39;s own doc) -- there is no next charge. Otherwise, advanced by one `period` on every successful renewal (`renew_market_subscriptions.rs`); left untouched once `canceled_at` is set, since a canceled subscription never renews again regardless of what this still says. |
| canceled_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | Set once the subscription will no longer renew -- either the buyer/admin explicitly canceled it (CancelMarketSubscription) or a renewal charge failed. The subscription&#39;s entitlement (media storage quota, granted permissions, etc.) stays active until whichever is later of renews_at/canceled_at, at which point renew_market_subscriptions.rs revokes it and sets service_terminated_at. Also the moment `MarketProduct.sold_count` is decremented, freeing this subscription&#39;s slot for a new buyer (see that field&#39;s own doc). |
| service_terminated_at | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional | The time permissions were removed, media storage quotas reset, etc. -- i.e. when `logic::market_fulfillment::terminate_entitlement` actually ran for this subscription. Always unset while `canceled_at` is unset; may remain unset for a while *after* `canceled_at` is set, since the entitlement intentionally stays active until the later of `renews_at`/`canceled_at` (see `canceled_at`&#39;s own doc) -- a buyer who cancels mid-period keeps what they already paid for through the end of that period. |






<a name="rellm-MediaStoragePurchaseDetails"></a>

### MediaStoragePurchaseDetails
`MarketPurchase.details`&#39; `PURCHASE_TYPE_MEDIA_STORAGE` variant -- copied verbatim from the
originating `MarketProduct.details` at the moment this purchase was fulfilled (see
`MarketPurchase.details`&#39; own doc). Field-for-field identical to
`MediaStorageSubscriptionDetails` -- kept as its own message only so the Purchase- and
Subscription-side `oneof`s stay independent Rust types (see
`logic::market_fulfillment::terminate_entitlement`&#39;s own doc for why that distinction matters
for `PermissionsAccessPurchaseDetails`/`PermissionsAccessSubscriptionDetails`).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| allocation_bytes | [uint64](#uint64) |  | The buyer&#39;s new total media storage allocation, replacing (not adding to) whatever quota they already had -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `MediaStorage` arm. |






<a name="rellm-MediaStorageSubscriptionDetails"></a>

### MediaStorageSubscriptionDetails
`MarketProduct.details`/`MarketSubscription.details`&#39; `PURCHASE_TYPE_MEDIA_STORAGE` variant --
what a media storage product actually grants. Field-for-field identical to
`MediaStoragePurchaseDetails` -- see that message&#39;s own doc for why it&#39;s still a distinct type.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| allocation_bytes | [uint64](#uint64) |  | How much media storage this product/subscription grants the buyer, replacing (not adding to) whatever quota they already had -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `MediaStorage` arm. |






<a name="rellm-PermissionsAccessPurchaseDetails"></a>

### PermissionsAccessPurchaseDetails
`MarketPurchase.details`&#39; `PURCHASE_TYPE_PERMISSIONS_ACCESS` variant -- copied verbatim from the
originating `MarketProduct.details` at the moment this purchase was fulfilled. Field-for-field
identical to `PermissionsAccessSubscriptionDetails`, but kept as a genuinely distinct Rust type
(not just documentation) -- see `logic::market_fulfillment::terminate_entitlement`&#39;s own doc,
which parses a `MarketSubscription`&#39;s `details` as `PermissionsAccessSubscriptionDetails`
specifically (never this message) when clawing back a lapsed grant.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| permissions | [Permission](#rellm-Permission) | repeated | The permissions this purchase granted -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `PermissionsAccess` arm (adds these to the buyer&#39;s `User.permissions`, union-style). |
| name | [string](#string) |  | Admin-authored product name shown for this purchase (e.g. on `/market/fulfillment`&#39;s billing history) -- copied from `PermissionsAccessSubscriptionDetails.name` at the moment this purchase was fulfilled. Unlike the other three purchase-detail messages&#39; implicit, Elm-computed display names, permissions-access products have no fixed bundle of permissions to describe generically, so an admin names/describes each one by hand. |
| description | [string](#string) |  | Admin-authored, Markdown-formatted product description -- copied from `PermissionsAccessSubscriptionDetails.description` the same way `name` above is. |






<a name="rellm-PermissionsAccessSubscriptionDetails"></a>

### PermissionsAccessSubscriptionDetails
`MarketProduct.details`/`MarketSubscription.details`&#39; `PURCHASE_TYPE_PERMISSIONS_ACCESS`
variant -- what a permissions-bundle product actually grants. Field-for-field identical to
`PermissionsAccessPurchaseDetails` -- see that message&#39;s own doc for why it&#39;s still a distinct
type (that distinction is exactly what lets `logic::market_fulfillment::terminate_entitlement`
tell &#34;what to claw back&#34; apart from &#34;what was originally billed&#34;).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| permissions | [Permission](#rellm-Permission) | repeated | Which `Permission`s this product/subscription grants the buyer -- see `logic::market_fulfillment::fulfill_purchase`&#39;s `PermissionsAccess` arm (union-added to the buyer&#39;s own `User.permissions`, never replacing what they already had) and `terminate_entitlement`&#39;s own arm (the exact claw-back set on cancellation/expiry). Intentionally excludes permissions dangerous or nonsensical to sell this way -- e.g. &#34;Grant Basic Permissions,&#34; any &#34;Moderate&#34;/&#34;Read All System Messages&#34; permission, &#34;Admin,&#34; &#34;View Private Contact Methods,&#34; and &#34;Edit Cluster Settings&#34; must never appear in a Market product&#39;s own `permissions` list. Enforced server-side on `CreateMarketProduct`/ `UpdateMarketProduct` (rejected with `permission_not_purchasable`) and again on `MakeMarketPurchase` (defense in depth, in case a permission is later removed from the purchasable set after a product granting it already exists) -- see `rpcs::market::create_market_product::PURCHASABLE_PERMISSIONS`. NOTE: that Rust list is an explicit include-list, not an exclude-list -- described here as an exclusion for readability, but implemented as &#34;only these permissions are purchasable&#34; so a newly-added `Permission` is never purchasable by default; it has to be deliberately added to that list. |
| name | [string](#string) |  | Admin-authored product name -- unlike `MediaStorageSubscriptionDetails`/`AIGrantSubscriptionDetails`/ `RellmHostingSubscriptionDetails` (which get an implicit, Elm-computed display name from their own fields, since they each describe one fixed kind of thing), a permissions-access product&#39;s `permissions` list can be any admin-chosen bundle, so there&#39;s no generic way to name it automatically. Required for a purchasable product (`CreateMarketProduct`/`UpdateMarketProduct` reject a `PermissionsAccessSubscriptionDetails` with a blank `name`). On a `MarketSubscription`: copied from the originating `MarketProduct.details.name` at the time the subscription was created, same as every other field on this message. |
| description | [string](#string) |  | Admin-authored, Markdown-formatted product description shown on the product&#39;s own page -- same &#34;no generic implicit description&#34; reasoning as `name` above. On a `MarketSubscription`: copied the same way `name` is. |






<a name="rellm-RellmHostingPurchaseDetails"></a>

### RellmHostingPurchaseDetails
`MarketPurchase.details`&#39; `PURCHASE_TYPE_RELLM_HOSTING` variant -- unlike the other three
`*PurchaseDetails` messages, NOT copied from the originating `MarketProduct.details`; instead
built fresh at checkout time from the buyer&#39;s own `MakeMarketPurchaseRequest.rellm_hosting_details`
(carried through as Stripe Checkout Session metadata -- see `rpcs::market::make_market_purchase`
and `web::stripe_webhook::handle_checkout_session_completed`). Field-for-field identical to
`RellmHostingSubscriptionDetails` (minus that message&#39;s `fulfillment_status`/`fulfillment_notes`) -- see
`MediaStoragePurchaseDetails`&#39;s own doc for why it&#39;s still a separate message.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| db_size_bytes | [uint64](#uint64) |  | NOTE: as of the current webhook implementation, the buyer never supplies this and the originating `MarketProduct`&#39;s own configured size isn&#39;t carried through Checkout Session metadata either, so this is currently always `0` here -- an admin fulfilling an order today needs to cross-reference the `MarketProduct` itself for the size actually sold. Intended to be the requested PostgreSQL database size in bytes. |
| minio_size_bytes | [uint64](#uint64) |  | Same caveat as `db_size_bytes` above -- currently always `0`. Intended to be the requested MinIO (object storage) size in bytes. |
| additional_description | [string](#string) |  | Copied from `RellmHostingSubscriptionDetails.additional_description` at the moment this purchase was fulfilled -- see that field&#39;s own doc. |
| domain | [string](#string) |  | The domain the buyer wants their new Rellm instance reachable at (e.g. &#34;myserver.example.com&#34;). |
| contact_email | [string](#string) |  | Where the fulfilling admin should reach the buyer about this order, separate from whatever email/contact info is on the buyer&#39;s own `User` (which may not be checked as often, or may not exist at all for a server with no email-based signup). |
| additional_information | [string](#string) |  | Free-form notes from the buyer to the fulfilling admin, captured once at purchase time (e.g. special requests, existing-data-migration needs). Immutable after purchase -- see `RellmHostingSubscriptionDetails.additional_information`&#39;s own doc, which carries this same text forward onto the resulting `MarketSubscription`. |






<a name="rellm-RellmHostingSubscriptionDetails"></a>

### RellmHostingSubscriptionDetails
`MarketProduct.details`/`MarketSubscription.details`&#39; `PURCHASE_TYPE_RELLM_HOSTING` variant --
what a dedicated-hosting product actually grants, plus the buyer&#39;s own request details and the
admin&#39;s own fulfillment tracking for it. Field-for-field identical to `RellmHostingPurchaseDetails`
for the first five fields (see that message&#39;s own doc); `fulfillment_status`/`fulfillment_notes` below have
no `*PurchaseDetails` counterpart, since they&#39;re only ever meaningful on the standing
`MarketSubscription`, not on any one individual `MarketPurchase` billing event.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| db_size_bytes | [uint64](#uint64) |  | On a `MarketProduct`: the PostgreSQL database size (in bytes) this product is configured to provision. On a `MarketSubscription`: see `RellmHostingPurchaseDetails.db_size_bytes`&#39;s own doc -- as of the current webhook implementation, this is currently always `0` here too, since the subscription&#39;s `details` is built the same way the purchase&#39;s is. |
| minio_size_bytes | [uint64](#uint64) |  | Same caveat as `db_size_bytes` above. On a `MarketProduct`: the MinIO (object storage) size (in bytes) this product is configured to provision. |
| additional_description | [string](#string) |  | Admin-authored, Markdown-formatted extra paragraph appended below the implicit, Elm-computed &#34;1GB DB &#43; 5GB Object Storage&#34;-style canned description shown on the product/subscription&#39;s own page -- e.g. to call out something specific to this hosting tier that the canned text doesn&#39;t cover. Optional; the canned description alone is shown when this is blank. |
| domain | [string](#string) |  | On a `MarketProduct`: unset/meaningless (a product isn&#39;t tied to any one domain). On a `MarketSubscription`: the domain the buyer wants their new Rellm instance reachable at, from `RellmHostingPurchaseDetails.domain`. |
| contact_email | [string](#string) |  | On a `MarketProduct`: unset/meaningless. On a `MarketSubscription`: where the fulfilling admin should reach the buyer about this order, from `RellmHostingPurchaseDetails.contact_email`. |
| additional_information | [string](#string) |  | Immutable after purchase -- the buyer&#39;s own notes to the admin fulfilling this order. Never editable via UpdateMarketSubscription (see that RPC&#39;s own doc); `fulfillment_notes` below is the admin/buyer conversation about fulfilling it. |
| fulfillment_status | [FulfillmentStatus](#rellm-FulfillmentStatus) |  | Where this Rellm hosting order currently stands -- Rellm hosting is deliberately not automated (see `market.proto`&#39;s own top-of-file notes and `logic::market_fulfillment::fulfill_purchase`&#39;s `RellmHosting` no-op arm), so this is the one manual &#34;how far along is this order&#34; signal, shown on `/market/fulfillment` (`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`). Never independently settable by a client -- always server-derived as whatever `fulfillment_notes`&#39; own last entry&#39;s `fulfillment_status` says (or `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` if `fulfillment_notes` is empty), so this field can never drift out of sync with the history that explains *why* it&#39;s in that state. |
| fulfillment_notes | [FulfillmentNote](#rellm-FulfillmentNote) | repeated | The admin/buyer conversation about fulfilling this order -- oldest to newest, append-only (see `UpdateMarketSubscription`&#39;s own doc: a new entry can only ever be appended after whatever&#39;s already here, never inserted/reordered/removed, and its `user_id` must match whoever&#39;s actually making the request -- the server stamps `created_at` itself). |





 


<a name="rellm-FulfillmentStatus"></a>

### FulfillmentStatus
The state of a `PURCHASE_TYPE_RELLM_HOSTING` order&#39;s manual fulfillment -- see
`RellmHostingSubscriptionDetails.fulfillment_status`&#39;s own doc for how the &#34;current&#34; value is
derived, and `FulfillmentNote.fulfillment_status` for how every transition is recorded as its own
timestamped note (a &#34;fulfillment state history&#34;), not just tracked as a bare current value.

| Name | Number | Description |
| ---- | ------ | ----------- |
| FULFILLMENT_STATUS_AWAITING_HOST_ADMIN | 0 | The starting state for every new order -- no admin has looked at it yet. |
| FULFILLMENT_STATUS_FULFILLED | 1 | The order is fully stood up -- set via &#34;Add and Mark as Fulfilled&#34; on `/market/fulfillment` (`UpdateMarketSubscription`). |
| FULFILLMENT_STATUS_IN_PROGRESS | 2 | An admin has started working the order but it isn&#39;t done yet -- set automatically the first time an admin expands this order&#39;s row on `/market/fulfillment` (if it was still `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN`), or explicitly via a note. |



<a name="rellm-GetMarketSubscriptionsRequestType"></a>

### GetMarketSubscriptionsRequestType


| Name | Number | Description |
| ---- | ------ | ----------- |
| GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE | 0 | The &#34;user facing&#34; view backing /market -- the caller&#39;s own MarketSubscriptions only. |
| GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN | 1 | Admin-only view backing /market/fulfillment -- every PURCHASE_TYPE_RELLM_HOSTING MarketSubscription across every buyer, since Rellm hosting needs manual setup that isn&#39;t automated (see RellmHostingSubscriptionDetails.fulfillment_status&#39;s own doc). |



<a name="rellm-PurchasePeriod"></a>

### PurchasePeriod
How often a `MarketProduct`/`MarketSubscription` bills. Immutable on a `MarketProduct` once
created (see that message&#39;s own doc) -- same reasoning as `PurchaseType`&#39;s immutability.

| Name | Number | Description |
| ---- | ------ | ----------- |
| PURCHASE_PERIOD_INDEFINITE | 0 | A single one-time purchase -- still creates a `MarketSubscription` alongside its `MarketPurchase` (see `MarketSubscription`&#39;s own doc), so it&#39;s still cancelable and still carries per-type fulfillment tracking (e.g. `RellmHostingSubscriptionDetails.fulfillment_status`/ `fulfillment_notes`) the same way a recurring one does -- it just has `renews_at` unset and never bills again. Canceling one takes effect immediately (see `MarketSubscription.canceled_at`&#39;s own doc: entitlement stays active until the later of `renews_at`/`canceled_at`, and an unset `renews_at` is never later than anything). |
| PURCHASE_PERIOD_ANNUAL | 1 | Renews (re-bills and re-fulfills) once per year, via `renew_market_subscriptions.rs`. |
| PURCHASE_PERIOD_MONTHLY | 2 | Renews (re-bills and re-fulfills) once per month, via `renew_market_subscriptions.rs`. |



<a name="rellm-PurchaseType"></a>

### PurchaseType
What a `MarketProduct`/`MarketPurchase`/`MarketSubscription` actually grants the buyer once
fulfilled -- see `logic::market_fulfillment::fulfill_purchase` (the Rust match on this same enum)
for exactly what each value does. Immutable on a `MarketProduct` once created (see that message&#39;s
own doc) -- changing what a product *is* after people have already bought it would silently
change existing buyers&#39; entitlements out from under them, so a product whose type needs to change
is delisted and replaced with a new one instead.

| Name | Number | Description |
| ---- | ------ | ----------- |
| PURCHASE_TYPE_MEDIA_STORAGE | 0 | Extra media storage allocation -- fulfillment sets the buyer&#39;s `User.media_storage_limit_bytes` to `MediaStoragePurchaseDetails.allocation_bytes` outright (not additive with any existing quota). On cancellation/expiry, reverts to the server&#39;s current configured default allocation (`ServerConfiguration.media_settings.default_media_allocation_bytes`), not to unlimited. |
| PURCHASE_TYPE_AI_GRANTS | 1 | AI provider token grants -- fulfillment resets (never adds to) the buyer&#39;s `AIProviderGrant.tokens_remaining` for `AIGrantPurchaseDetails.ai_provider_id`/`model_names` to `AIGrantPurchaseDetails.tokens`, same &#34;reset, don&#39;t add&#34; semantics every renewal uses. Not automatically revoked on cancellation/expiry -- whatever tokens remain when the subscription lapses just aren&#39;t replenished again. |
| PURCHASE_TYPE_RELLM_HOSTING | 2 | A dedicated Rellm server instance, hosted and administered by Jon. Deliberately NOT automated -- fulfillment applies no entitlement at all; an admin provisions the server by hand and tracks progress via `RellmHostingSubscriptionDetails.fulfillment_status`/`fulfillment_notes` on the `/market/fulfillment` admin page. Not automatically revoked on cancellation/expiry either (out of scope for this MVP -- an admin handles teardown manually too). |
| PURCHASE_TYPE_PERMISSIONS_ACCESS | 3 | A bundle of `Permission`s (e.g. `SYNC_EVENTS_TO_FACEBOOK`) granted directly to the buyer&#39;s own `User.permissions`, union-style -- fulfillment only ever adds permissions the buyer doesn&#39;t already have from some other source, never removes any. Unlike the other three types, this ONE eventually claws back what it granted: once cancellation/expiry actually takes effect (see `MarketSubscription.canceled_at`/`service_terminated_at`), `logic::market_fulfillment:: terminate_entitlement` removes exactly the permissions this subscription granted (a plain set difference, not a reconciliation against any other subscription/grant the buyer might also hold). |


 

 

 



## Scalar Value Types

| .proto Type | Notes | C++ | Java | Python | Go | C# | PHP | Ruby |
| ----------- | ----- | --- | ---- | ------ | -- | -- | --- | ---- |
| <a name="double" /> double |  | double | double | float | float64 | double | float | Float |
| <a name="float" /> float |  | float | float | float | float32 | float | float | Float |
| <a name="int32" /> int32 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint32 instead. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="int64" /> int64 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint64 instead. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="uint32" /> uint32 | Uses variable-length encoding. | uint32 | int | int/long | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="uint64" /> uint64 | Uses variable-length encoding. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum or Fixnum (as required) |
| <a name="sint32" /> sint32 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int32s. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sint64" /> sint64 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int64s. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="fixed32" /> fixed32 | Always four bytes. More efficient than uint32 if values are often greater than 2^28. | uint32 | int | int | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="fixed64" /> fixed64 | Always eight bytes. More efficient than uint64 if values are often greater than 2^56. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum |
| <a name="sfixed32" /> sfixed32 | Always four bytes. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sfixed64" /> sfixed64 | Always eight bytes. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="bool" /> bool |  | bool | boolean | boolean | bool | bool | boolean | TrueClass/FalseClass |
| <a name="string" /> string | A string must always contain UTF-8 encoded or 7-bit ASCII text. | string | String | str/unicode | string | string | string | String (UTF-8) |
| <a name="bytes" /> bytes | May contain any arbitrary sequence of bytes. | string | ByteString | str | []byte | ByteString | string | String (ASCII-8BIT) |

