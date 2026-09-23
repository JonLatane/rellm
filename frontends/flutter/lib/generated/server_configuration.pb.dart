//
//  Generated code. Do not modify.
//  source: server_configuration.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'federation.pb.dart' as $1;
import 'google/protobuf/timestamp.pb.dart' as $13;
import 'permissions.pbenum.dart' as $15;
import 'server_configuration.pbenum.dart';
import 'visibility_moderation.pbenum.dart' as $14;

export 'server_configuration.pbenum.dart';

/// Configuration for a Rellm server instance.
class ServerConfiguration extends $pb.GeneratedMessage {
  factory ServerConfiguration({
    ServerInfo? serverInfo,
    $1.FederationInfo? federationInfo,
    $core.Iterable<$15.Permission>? anonymousUserPermissions,
    $core.Iterable<$15.Permission>? defaultUserPermissions,
    $core.Iterable<$15.Permission>? basicUserPermissions,
    CustomNavigationTabSet? customTabs,
    FeatureSettings? peopleSettings,
    FeatureSettings? groupSettings,
    PostSettings? postSettings,
    EventSettings? eventSettings,
    MediaSettings? mediaSettings,
    MarketSettings? marketSettings,
    ExternalCDNConfig? externalCdnConfig,
    ClusterResources? clusterResources,
    PrivateUserStrategy? privateUserStrategy,
    $core.Iterable<AuthenticationFeature>? authenticationFeatures,
    WebPushConfig? webPushConfig,
    $core.Iterable<ContactProtocol>? supportedContactProtocols,
    $core.Iterable<ContactVerificationAPI>? preferredVerificationApis,
    $core.Iterable<ContactVerificationAPI>? availableVerificationApis,
    TwilioConfig? twilioConfig,
    BirdConfig? birdConfig,
    StripeConfig? stripeConfig,
    TelnyxConfig? telnyxConfig,
    StalwartConfig? stalwartConfig,
  }) {
    final $result = create();
    if (serverInfo != null) {
      $result.serverInfo = serverInfo;
    }
    if (federationInfo != null) {
      $result.federationInfo = federationInfo;
    }
    if (anonymousUserPermissions != null) {
      $result.anonymousUserPermissions.addAll(anonymousUserPermissions);
    }
    if (defaultUserPermissions != null) {
      $result.defaultUserPermissions.addAll(defaultUserPermissions);
    }
    if (basicUserPermissions != null) {
      $result.basicUserPermissions.addAll(basicUserPermissions);
    }
    if (customTabs != null) {
      $result.customTabs = customTabs;
    }
    if (peopleSettings != null) {
      $result.peopleSettings = peopleSettings;
    }
    if (groupSettings != null) {
      $result.groupSettings = groupSettings;
    }
    if (postSettings != null) {
      $result.postSettings = postSettings;
    }
    if (eventSettings != null) {
      $result.eventSettings = eventSettings;
    }
    if (mediaSettings != null) {
      $result.mediaSettings = mediaSettings;
    }
    if (marketSettings != null) {
      $result.marketSettings = marketSettings;
    }
    if (externalCdnConfig != null) {
      $result.externalCdnConfig = externalCdnConfig;
    }
    if (clusterResources != null) {
      $result.clusterResources = clusterResources;
    }
    if (privateUserStrategy != null) {
      $result.privateUserStrategy = privateUserStrategy;
    }
    if (authenticationFeatures != null) {
      $result.authenticationFeatures.addAll(authenticationFeatures);
    }
    if (webPushConfig != null) {
      $result.webPushConfig = webPushConfig;
    }
    if (supportedContactProtocols != null) {
      $result.supportedContactProtocols.addAll(supportedContactProtocols);
    }
    if (preferredVerificationApis != null) {
      $result.preferredVerificationApis.addAll(preferredVerificationApis);
    }
    if (availableVerificationApis != null) {
      $result.availableVerificationApis.addAll(availableVerificationApis);
    }
    if (twilioConfig != null) {
      $result.twilioConfig = twilioConfig;
    }
    if (birdConfig != null) {
      $result.birdConfig = birdConfig;
    }
    if (stripeConfig != null) {
      $result.stripeConfig = stripeConfig;
    }
    if (telnyxConfig != null) {
      $result.telnyxConfig = telnyxConfig;
    }
    if (stalwartConfig != null) {
      $result.stalwartConfig = stalwartConfig;
    }
    return $result;
  }
  ServerConfiguration._() : super();
  factory ServerConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ServerConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ServerConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<ServerInfo>(1, _omitFieldNames ? '' : 'serverInfo', subBuilder: ServerInfo.create)
    ..aOM<$1.FederationInfo>(2, _omitFieldNames ? '' : 'federationInfo', subBuilder: $1.FederationInfo.create)
    ..pc<$15.Permission>(10, _omitFieldNames ? '' : 'anonymousUserPermissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..pc<$15.Permission>(11, _omitFieldNames ? '' : 'defaultUserPermissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..pc<$15.Permission>(12, _omitFieldNames ? '' : 'basicUserPermissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..aOM<CustomNavigationTabSet>(19, _omitFieldNames ? '' : 'customTabs', subBuilder: CustomNavigationTabSet.create)
    ..aOM<FeatureSettings>(20, _omitFieldNames ? '' : 'peopleSettings', subBuilder: FeatureSettings.create)
    ..aOM<FeatureSettings>(21, _omitFieldNames ? '' : 'groupSettings', subBuilder: FeatureSettings.create)
    ..aOM<PostSettings>(22, _omitFieldNames ? '' : 'postSettings', subBuilder: PostSettings.create)
    ..aOM<EventSettings>(23, _omitFieldNames ? '' : 'eventSettings', subBuilder: EventSettings.create)
    ..aOM<MediaSettings>(24, _omitFieldNames ? '' : 'mediaSettings', subBuilder: MediaSettings.create)
    ..aOM<MarketSettings>(25, _omitFieldNames ? '' : 'marketSettings', subBuilder: MarketSettings.create)
    ..aOM<ExternalCDNConfig>(90, _omitFieldNames ? '' : 'externalCdnConfig', subBuilder: ExternalCDNConfig.create)
    ..aOM<ClusterResources>(91, _omitFieldNames ? '' : 'clusterResources', subBuilder: ClusterResources.create)
    ..e<PrivateUserStrategy>(100, _omitFieldNames ? '' : 'privateUserStrategy', $pb.PbFieldType.OE, defaultOrMaker: PrivateUserStrategy.ACCOUNT_IS_FROZEN, valueOf: PrivateUserStrategy.valueOf, enumValues: PrivateUserStrategy.values)
    ..pc<AuthenticationFeature>(101, _omitFieldNames ? '' : 'authenticationFeatures', $pb.PbFieldType.KE, valueOf: AuthenticationFeature.valueOf, enumValues: AuthenticationFeature.values, defaultEnumValue: AuthenticationFeature.AUTHENTICATION_FEATURE_UNKNOWN)
    ..aOM<WebPushConfig>(110, _omitFieldNames ? '' : 'webPushConfig', subBuilder: WebPushConfig.create)
    ..pc<ContactProtocol>(119, _omitFieldNames ? '' : 'supportedContactProtocols', $pb.PbFieldType.KE, valueOf: ContactProtocol.valueOf, enumValues: ContactProtocol.values, defaultEnumValue: ContactProtocol.CONTACT_PROTOCOL_TEL)
    ..pc<ContactVerificationAPI>(120, _omitFieldNames ? '' : 'preferredVerificationApis', $pb.PbFieldType.KE, valueOf: ContactVerificationAPI.valueOf, enumValues: ContactVerificationAPI.values, defaultEnumValue: ContactVerificationAPI.CONTACT_VERIFICATION_API_TWILIO)
    ..pc<ContactVerificationAPI>(121, _omitFieldNames ? '' : 'availableVerificationApis', $pb.PbFieldType.KE, valueOf: ContactVerificationAPI.valueOf, enumValues: ContactVerificationAPI.values, defaultEnumValue: ContactVerificationAPI.CONTACT_VERIFICATION_API_TWILIO)
    ..aOM<TwilioConfig>(122, _omitFieldNames ? '' : 'twilioConfig', subBuilder: TwilioConfig.create)
    ..aOM<BirdConfig>(123, _omitFieldNames ? '' : 'birdConfig', subBuilder: BirdConfig.create)
    ..aOM<StripeConfig>(124, _omitFieldNames ? '' : 'stripeConfig', subBuilder: StripeConfig.create)
    ..aOM<TelnyxConfig>(125, _omitFieldNames ? '' : 'telnyxConfig', subBuilder: TelnyxConfig.create)
    ..aOM<StalwartConfig>(126, _omitFieldNames ? '' : 'stalwartConfig', subBuilder: StalwartConfig.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ServerConfiguration clone() => ServerConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ServerConfiguration copyWith(void Function(ServerConfiguration) updates) => super.copyWith((message) => updates(message as ServerConfiguration)) as ServerConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerConfiguration create() => ServerConfiguration._();
  ServerConfiguration createEmptyInstance() => create();
  static $pb.PbList<ServerConfiguration> createRepeated() => $pb.PbList<ServerConfiguration>();
  @$core.pragma('dart2js:noInline')
  static ServerConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerConfiguration>(create);
  static ServerConfiguration? _defaultInstance;

  /// The name, description, logo, color scheme, etc. of the server.
  @$pb.TagNumber(1)
  ServerInfo get serverInfo => $_getN(0);
  @$pb.TagNumber(1)
  set serverInfo(ServerInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasServerInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearServerInfo() => clearField(1);
  @$pb.TagNumber(1)
  ServerInfo ensureServerInfo() => $_ensure(0);

  /// The federation configuration for the server.
  @$pb.TagNumber(2)
  $1.FederationInfo get federationInfo => $_getN(1);
  @$pb.TagNumber(2)
  set federationInfo($1.FederationInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasFederationInfo() => $_has(1);
  @$pb.TagNumber(2)
  void clearFederationInfo() => clearField(2);
  @$pb.TagNumber(2)
  $1.FederationInfo ensureFederationInfo() => $_ensure(1);

  /// Permissions for a user who isn't logged in to the server. Allows
  /// admins to disable certain features for anonymous users. Valid values are
  /// `VIEW_USERS`, `VIEW_GROUPS`, `VIEW_POSTS`, and `VIEW_EVENTS`.
  @$pb.TagNumber(10)
  $core.List<$15.Permission> get anonymousUserPermissions => $_getList(2);

  /// Default user permissions given to a new user. Users with `MODERATE_USERS` permission can also
  /// grant/revoke these permissions for others. Valid values are
  /// `VIEW_USERS`, `PUBLISH_USERS_LOCALLY`, `PUBLISH_USERS_GLOBALLY`,
  /// `VIEW_GROUPS`, `CREATE_GROUPS`, `PUBLISH_GROUPS_LOCALLY`, `PUBLISH_GROUPS_GLOBALLY`, `JOIN_GROUPS`,
  /// `VIEW_POSTS`, `CREATE_POSTS`, `PUBLISH_POSTS_LOCALLY`, `PUBLISH_POSTS_GLOBALLY`,
  /// `VIEW_EVENTS`, `CREATE_EVENTS`, `PUBLISH_EVENTS_LOCALLY`, and `PUBLISH_EVENTS_GLOBALLY`.
  @$pb.TagNumber(11)
  $core.List<$15.Permission> get defaultUserPermissions => $_getList(3);

  /// Permissions grantable by a user with the `GRANT_BASIC_PERMISSIONS` permission. Valid values are
  /// `VIEW_USERS`, `PUBLISH_USERS_LOCALLY`, `PUBLISH_USERS_GLOBALLY`,
  /// `VIEW_GROUPS`, `CREATE_GROUPS`, `PUBLISH_GROUPS_LOCALLY`, `PUBLISH_GROUPS_GLOBALLY`, `JOIN_GROUPS`,
  /// `VIEW_POSTS`, `CREATE_POSTS`, `PUBLISH_POSTS_LOCALLY`, `PUBLISH_POSTS_GLOBALLY`,
  /// `VIEW_EVENTS`, `CREATE_EVENTS`, `PUBLISH_EVENTS_LOCALLY`, and `PUBLISH_EVENTS_GLOBALLY`.
  @$pb.TagNumber(12)
  $core.List<$15.Permission> get basicUserPermissions => $_getList(4);

  @$pb.TagNumber(19)
  CustomNavigationTabSet get customTabs => $_getN(5);
  @$pb.TagNumber(19)
  set customTabs(CustomNavigationTabSet v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasCustomTabs() => $_has(5);
  @$pb.TagNumber(19)
  void clearCustomTabs() => clearField(19);
  @$pb.TagNumber(19)
  CustomNavigationTabSet ensureCustomTabs() => $_ensure(5);

  /// Configuration for users on the server.
  /// If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must*
  /// contain `PUBLISH_USERS_GLOBALLY`.
  @$pb.TagNumber(20)
  FeatureSettings get peopleSettings => $_getN(6);
  @$pb.TagNumber(20)
  set peopleSettings(FeatureSettings v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasPeopleSettings() => $_has(6);
  @$pb.TagNumber(20)
  void clearPeopleSettings() => clearField(20);
  @$pb.TagNumber(20)
  FeatureSettings ensurePeopleSettings() => $_ensure(6);

  /// Configuration for groups on the server.
  /// If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must*
  /// contain `PUBLISH_GROUPS_GLOBALLY`.
  @$pb.TagNumber(21)
  FeatureSettings get groupSettings => $_getN(7);
  @$pb.TagNumber(21)
  set groupSettings(FeatureSettings v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasGroupSettings() => $_has(7);
  @$pb.TagNumber(21)
  void clearGroupSettings() => clearField(21);
  @$pb.TagNumber(21)
  FeatureSettings ensureGroupSettings() => $_ensure(7);

  /// Configuration for posts on the server.
  /// If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must*
  /// contain `PUBLISH_POSTS_GLOBALLY`.
  @$pb.TagNumber(22)
  PostSettings get postSettings => $_getN(8);
  @$pb.TagNumber(22)
  set postSettings(PostSettings v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasPostSettings() => $_has(8);
  @$pb.TagNumber(22)
  void clearPostSettings() => clearField(22);
  @$pb.TagNumber(22)
  PostSettings ensurePostSettings() => $_ensure(8);

  /// Configuration for events on the server.
  /// If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must*
  /// contain `PUBLISH_EVENTS_GLOBALLY`.
  @$pb.TagNumber(23)
  EventSettings get eventSettings => $_getN(9);
  @$pb.TagNumber(23)
  set eventSettings(EventSettings v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasEventSettings() => $_has(9);
  @$pb.TagNumber(23)
  void clearEventSettings() => clearField(23);
  @$pb.TagNumber(23)
  EventSettings ensureEventSettings() => $_ensure(9);

  /// Configuration for media on the server.
  /// If default visibility is `GLOBAL_PUBLIC`, default_user_permissions *must*
  /// contain `PUBLISH_MEDIA_GLOBALLY`.
  @$pb.TagNumber(24)
  MediaSettings get mediaSettings => $_getN(10);
  @$pb.TagNumber(24)
  set mediaSettings(MediaSettings v) { setField(24, v); }
  @$pb.TagNumber(24)
  $core.bool hasMediaSettings() => $_has(10);
  @$pb.TagNumber(24)
  void clearMediaSettings() => clearField(24);
  @$pb.TagNumber(24)
  MediaSettings ensureMediaSettings() => $_ensure(10);

  /// Public, non-secret "is this server's Market open" signal -- unlike `stripe_config` (which holds
  /// real credentials and is Admin-only, see that field's own doc), this is never stripped for a
  /// non-admin/unauthenticated caller. Lets a client decide whether to show this server's Market
  /// section at all (e.g. when browsing a federated list of servers) without needing to be an admin
  /// here just to check -- see `rellm.proto`'s own "Federated Markets" doc section.
  @$pb.TagNumber(25)
  MarketSettings get marketSettings => $_getN(11);
  @$pb.TagNumber(25)
  set marketSettings(MarketSettings v) { setField(25, v); }
  @$pb.TagNumber(25)
  $core.bool hasMarketSettings() => $_has(11);
  @$pb.TagNumber(25)
  void clearMarketSettings() => clearField(25);
  @$pb.TagNumber(25)
  MarketSettings ensureMarketSettings() => $_ensure(11);

  /// If set, enables External CDN support for the server. This means that the
  /// non-secure HTTP server (on port 80) will *not* redirect to the secure server,
  /// and instead serve up Tamagui Web/Flutter clients directly. This allows you
  /// to point Cloudflare's "CNAME HTTPS Proxy" feature at your Rellm server to serve
  /// up HTML/CS/JS and Media files with caching from Cloudflare's CDN.
  /// See ExternalCDNConfig for more details on securing this setup.
  @$pb.TagNumber(90)
  ExternalCDNConfig get externalCdnConfig => $_getN(12);
  @$pb.TagNumber(90)
  set externalCdnConfig(ExternalCDNConfig v) { setField(90, v); }
  @$pb.TagNumber(90)
  $core.bool hasExternalCdnConfig() => $_has(12);
  @$pb.TagNumber(90)
  void clearExternalCdnConfig() => clearField(90);
  @$pb.TagNumber(90)
  ExternalCDNConfig ensureExternalCdnConfig() => $_ensure(12);

  /// Cluster-internal coordination state - see `ClusterResources`'s own doc. Visible to any
  /// logged-in admin (unlike most fields here, this describes infrastructure topology rather than
  /// anything end users need, so it's stripped entirely from
  /// [`GetServerConfiguration`](#grpc-api-GetServerConfiguration) for non-admins/anonymous
  /// callers); editing it via [`ConfigureServer`](#grpc-api-ConfigureServer) additionally requires
  /// the [`EDIT_CLUSTER_SETTINGS`](#rellm-Permission) permission.
  @$pb.TagNumber(91)
  ClusterResources get clusterResources => $_getN(13);
  @$pb.TagNumber(91)
  set clusterResources(ClusterResources v) { setField(91, v); }
  @$pb.TagNumber(91)
  $core.bool hasClusterResources() => $_has(13);
  @$pb.TagNumber(91)
  void clearClusterResources() => clearField(91);
  @$pb.TagNumber(91)
  ClusterResources ensureClusterResources() => $_ensure(13);

  /// Strategy when a user sets their visibility to `PRIVATE`. Defaults to `ACCOUNT_IS_FROZEN`.
  @$pb.TagNumber(100)
  PrivateUserStrategy get privateUserStrategy => $_getN(14);
  @$pb.TagNumber(100)
  set privateUserStrategy(PrivateUserStrategy v) { setField(100, v); }
  @$pb.TagNumber(100)
  $core.bool hasPrivateUserStrategy() => $_has(14);
  @$pb.TagNumber(100)
  void clearPrivateUserStrategy() => clearField(100);

  /// (TODO) Allows admins to enable/disable creating accounts and logging in.
  /// Eventually, external auth too hopefully!
  @$pb.TagNumber(101)
  $core.List<AuthenticationFeature> get authenticationFeatures => $_getList(15);

  /// Web Push (VAPID) configuration for the server.
  @$pb.TagNumber(110)
  WebPushConfig get webPushConfig => $_getN(16);
  @$pb.TagNumber(110)
  set webPushConfig(WebPushConfig v) { setField(110, v); }
  @$pb.TagNumber(110)
  $core.bool hasWebPushConfig() => $_has(16);
  @$pb.TagNumber(110)
  void clearWebPushConfig() => clearField(110);
  @$pb.TagNumber(110)
  WebPushConfig ensureWebPushConfig() => $_ensure(16);

  /// Which [`ContactProtocol`](#rellm-ContactProtocol)s (`tel:`/`mailto:`) this server currently
  /// accepts -- drives [`ContactMethod.supported_by_server`](#rellm-ContactMethod) (`users.proto`,
  /// which can't reference this message directly -- see that field's own doc for why). Settable via
  /// [`ConfigureServer`](#grpc-api-ConfigureServer), which *errors* rather than silently dropping an
  /// invalid entry: `CONTACT_PROTOCOL_TEL` requires an enabled
  /// [`TwilioConfig`](#rellm-TwilioConfig)/[`BirdConfig`](#rellm-BirdConfig)/
  /// [`TelnyxConfig`](#rellm-TelnyxConfig) in that same request, and `CONTACT_PROTOCOL_MAILTO` is
  /// always rejected (no email provider exists yet). Edited via the "Enable SMS Sending"/"Enable
  /// Email Sending" toggles on the Contact Integrations tab's "SMS Configuration"/"Email
  /// Configuration" sections (`ContactIntegrationsTab.smsConfigurationSection`/
  /// `emailConfigurationSection`) -- see `docs/contact_integrations.md`.
  @$pb.TagNumber(119)
  $core.List<ContactProtocol> get supportedContactProtocols => $_getList(17);

  /// A server-preferred order of [`ContactVerificationAPI`](#rellm-ContactVerificationAPI)
  /// providers to try first when more than one of `twilio_config`/`bird_config`/`telnyx_config`
  /// below is enabled -- see `contact_verification::available_verification_apis` for the full
  /// preference-then-fallback ordering this feeds into
  /// [`ServerConfiguration.available_verification_apis`](#rellm-ServerConfiguration) below. Even
  /// when this is blank, an enabled provider is still tried (in the fixed default order
  /// Twilio/Bird/Telnyx) -- this field only matters when more than one is enabled and the admin
  /// wants a specific one tried first. Only serialized for admin users.
  @$pb.TagNumber(120)
  $core.List<ContactVerificationAPI> get preferredVerificationApis => $_getList(18);

  /// Derived from whether [`TwilioConfig`](#rellm-TwilioConfig).twilio_enabled/
  /// [`BirdConfig`](#rellm-BirdConfig).bird_enabled/
  /// [`TelnyxConfig`](#rellm-TelnyxConfig).telnyx_enabled is true, ordered per
  /// `preferred_verification_apis` above. Serialized to every caller (not admin-only, unlike
  /// `preferred_verification_apis`/`twilio_config`/`bird_config`/`telnyx_config`) -- this is what a
  /// non-admin client should check to decide whether to show verification UI at all, without
  /// exposing any provider configuration. Independent of `supported_contact_protocols` above --
  /// that's the admin's own on/off toggle (can disable `tel:` contact even while a provider stays
  /// enabled/configured), this is purely "is at least one provider actually configured."
  @$pb.TagNumber(121)
  $core.List<ContactVerificationAPI> get availableVerificationApis => $_getList(19);

  /// Twilio Config -- see [`TwilioConfig`](#rellm-TwilioConfig). Only serialized for admin users.
  @$pb.TagNumber(122)
  TwilioConfig get twilioConfig => $_getN(20);
  @$pb.TagNumber(122)
  set twilioConfig(TwilioConfig v) { setField(122, v); }
  @$pb.TagNumber(122)
  $core.bool hasTwilioConfig() => $_has(20);
  @$pb.TagNumber(122)
  void clearTwilioConfig() => clearField(122);
  @$pb.TagNumber(122)
  TwilioConfig ensureTwilioConfig() => $_ensure(20);

  /// Bird (bird.com, formerly MessageBird) Config -- a cheaper alternative to
  /// [`TwilioConfig`](#rellm-TwilioConfig) for SMS verification; see
  /// [`BirdConfig`](#rellm-BirdConfig)'s own doc. Only serialized for admin users.
  @$pb.TagNumber(123)
  BirdConfig get birdConfig => $_getN(21);
  @$pb.TagNumber(123)
  set birdConfig(BirdConfig v) { setField(123, v); }
  @$pb.TagNumber(123)
  $core.bool hasBirdConfig() => $_has(21);
  @$pb.TagNumber(123)
  void clearBirdConfig() => clearField(123);
  @$pb.TagNumber(123)
  BirdConfig ensureBirdConfig() => $_ensure(21);

  /// Stripe Config, backing the Marketplace (`market.proto`). Only serialized for admin users.
  @$pb.TagNumber(124)
  StripeConfig get stripeConfig => $_getN(22);
  @$pb.TagNumber(124)
  set stripeConfig(StripeConfig v) { setField(124, v); }
  @$pb.TagNumber(124)
  $core.bool hasStripeConfig() => $_has(22);
  @$pb.TagNumber(124)
  void clearStripeConfig() => clearField(124);
  @$pb.TagNumber(124)
  StripeConfig ensureStripeConfig() => $_ensure(22);

  /// Telnyx Config -- another alternative SMS verification provider to
  /// [`TwilioConfig`](#rellm-TwilioConfig) (see [`TelnyxConfig`](#rellm-TelnyxConfig)'s own doc).
  /// Only serialized for admin users.
  @$pb.TagNumber(125)
  TelnyxConfig get telnyxConfig => $_getN(23);
  @$pb.TagNumber(125)
  set telnyxConfig(TelnyxConfig v) { setField(125, v); }
  @$pb.TagNumber(125)
  $core.bool hasTelnyxConfig() => $_has(23);
  @$pb.TagNumber(125)
  void clearTelnyxConfig() => clearField(125);
  @$pb.TagNumber(125)
  TelnyxConfig ensureTelnyxConfig() => $_ensure(23);

  ///  Unlike the other configs, at least at the moment, the integration with Stalwart is designed
  ///  to be *in-cluster*, not over the web. It relies on unsecured /email endpoint on port 27705
  ///  to receive mail from a Stalwart deployed within the same Kubernetes cluster.
  ///
  ///  This could be extended in the future to allow sending mail with Stalwart, but that's TBD.
  @$pb.TagNumber(126)
  StalwartConfig get stalwartConfig => $_getN(24);
  @$pb.TagNumber(126)
  set stalwartConfig(StalwartConfig v) { setField(126, v); }
  @$pb.TagNumber(126)
  $core.bool hasStalwartConfig() => $_has(24);
  @$pb.TagNumber(126)
  void clearStalwartConfig() => clearField(126);
  @$pb.TagNumber(126)
  StalwartConfig ensureStalwartConfig() => $_ensure(24);
}

///  Coordinates a small piece of shared, cluster-wide state across multiple independent Rellm
///  server instances that are otherwise fully isolated from each other (separate databases, separate
///  [`FederationInfo`](#rellm-FederationInfo), etc.) but happen to run on shared underlying
///  infrastructure (e.g. several Kubernetes namespaces sharing one small node pool). Currently used
///  for exactly one thing: making sure only one instance has a headless Chrome/Brave browser open at
///  any given moment (for generating link preview images), since launching several at once can
///  exhaust a shared node's CPU/memory. One participating instance is designated the "conductor" (see
///  `conductor_host`) and brokers locks via
///  [`LockClusterResources`](#grpc-api-LockClusterResources)/
///  [`FreeClusterResources`](#grpc-api-FreeClusterResources); every instance in the cluster --
///  including the conductor itself - sets its own `ClusterResources` pointing at whichever host
///  that is.
///
///  See `ServerConfiguration.cluster_resources`'s own doc for who can see/edit this.
class ClusterResources extends $pb.GeneratedMessage {
  factory ClusterResources({
    $core.String? namespaceId,
    $core.String? conductorHost,
    $core.String? clusterSharedSecret,
    ClusterConductorState? conductorState,
  }) {
    final $result = create();
    if (namespaceId != null) {
      $result.namespaceId = namespaceId;
    }
    if (conductorHost != null) {
      $result.conductorHost = conductorHost;
    }
    if (clusterSharedSecret != null) {
      $result.clusterSharedSecret = clusterSharedSecret;
    }
    if (conductorState != null) {
      $result.conductorState = conductorState;
    }
    return $result;
  }
  ClusterResources._() : super();
  factory ClusterResources.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClusterResources.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClusterResources', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'namespaceId')
    ..aOS(2, _omitFieldNames ? '' : 'conductorHost')
    ..aOS(3, _omitFieldNames ? '' : 'clusterSharedSecret')
    ..aOM<ClusterConductorState>(4, _omitFieldNames ? '' : 'conductorState', subBuilder: ClusterConductorState.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClusterResources clone() => ClusterResources()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClusterResources copyWith(void Function(ClusterResources) updates) => super.copyWith((message) => updates(message as ClusterResources)) as ClusterResources;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClusterResources create() => ClusterResources._();
  ClusterResources createEmptyInstance() => create();
  static $pb.PbList<ClusterResources> createRepeated() => $pb.PbList<ClusterResources>();
  @$core.pragma('dart2js:noInline')
  static ClusterResources getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClusterResources>(create);
  static ClusterResources? _defaultInstance;

  /// Identifies this instance to the conductor - e.g. its Kubernetes namespace. Passed as
  /// `LockClusterResourcesRequest.namespace_id`/`FreeClusterResourcesRequest.namespace_id` so the
  /// conductor knows who's asking, and echoed back as `ClusterResourceLock.lock_holder_namespace_id`
  /// while this instance holds a lock. By convention (not enforced - see `cluster_shared_secret`'s
  /// own doc), the conductor sets its own `namespace_id` equal to its own `conductor_host`; clients
  /// (e.g. the Elm `ClusterTab`) use that convention purely for display, to tell "this instance is
  /// the conductor" from "some other instance is."
  @$pb.TagNumber(1)
  $core.String get namespaceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set namespaceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNamespaceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNamespaceId() => clearField(1);

  ///  DNS hostname of whichever instance in the cluster is the "conductor" - the single instance
  ///  that actually brokers [`LockClusterResources`](#grpc-api-LockClusterResources)/
  ///  [`FreeClusterResources`](#grpc-api-FreeClusterResources) calls for every other instance
  ///  (including, by convention, itself - see `conductor_state`). Every instance in the cluster
  ///  points this at the same host.
  ///
  ///  Note: callers should resolve this the same way any other cross-server Rellm call does --
  ///  via [`GET {conductor_host}/backend_host`](#http-based-client-host-negotiation-for-external-cdns-get-backend_host)
  ///  first, falling back to `conductor_host` itself - rather than connecting to it directly, in
  ///  case the conductor sits behind an [`ExternalCDNConfig`](#rellm-ExternalCDNConfig).
  @$pb.TagNumber(2)
  $core.String get conductorHost => $_getSZ(1);
  @$pb.TagNumber(2)
  set conductorHost($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConductorHost() => $_has(1);
  @$pb.TagNumber(2)
  void clearConductorHost() => clearField(2);

  /// Shared secret proving a `LockClusterResources`/`FreeClusterResources` caller is a legitimate
  /// member of this cluster, passed as the `cluster-shared-secret` gRPC metadata header (not a
  /// request field - there's no per-user auth involved in these calls at all, just this secret).
  /// The receiving server checks it against its own stored `cluster_shared_secret` - that's the
  /// *entire* authorization check: knowing the secret is what makes a caller entitled to treat that
  /// server as the conductor, regardless of what that server's own `namespace_id`/`conductor_host`
  /// happen to say (see `namespace_id`'s own doc on that being a display-only convention). Write-only, like
  /// [`FacebookAuthConfig.app_secret`](#rellm-FacebookAuthConfig)/
  /// [`WebPushConfig.private_vapid_key`](#rellm-WebPushConfig) - `GetServerConfiguration` never
  /// sends the real value back to *any* client (not even an admin), and an empty incoming value on
  /// `ConfigureServer` means "leave the stored secret alone," not "clear it." Should never be
  /// transmitted over a non-TLS connection.
  @$pb.TagNumber(3)
  $core.String get clusterSharedSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set clusterSharedSecret($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasClusterSharedSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearClusterSharedSecret() => clearField(3);

  /// The conductor's live view of who currently holds each `ClusterResource`'s lock. Only ever
  /// populated on whichever instance actually receives (and grants) `LockClusterResources` calls --
  /// in a correctly configured cluster, that's the one instance every participant points
  /// `conductor_host` at (see that field's own doc), but nothing server-side enforces that; every
  /// other instance simply never gets asked to hold this state. Reflects the database directly, updated in place by
  /// `LockClusterResources`/`FreeClusterResources` - unlike the rest of `ServerConfiguration`,
  /// [`ConfigureServer`](#grpc-api-ConfigureServer) never lets a caller change this, and it isn't
  /// versioned the way other `ConfigureServer` changes are.
  @$pb.TagNumber(4)
  ClusterConductorState get conductorState => $_getN(3);
  @$pb.TagNumber(4)
  set conductorState(ClusterConductorState v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasConductorState() => $_has(3);
  @$pb.TagNumber(4)
  void clearConductorState() => clearField(4);
  @$pb.TagNumber(4)
  ClusterConductorState ensureConductorState() => $_ensure(3);
}

/// The conductor's live view of currently-held locks - one `ClusterResourceLock` per distinct
/// holder (a given namespace can appear at most once here - `LockClusterResources` never grants a
/// `ClusterResource` it's already granted that same `namespace_id`, and folds any additional
/// resources into that namespace's existing entry rather than creating a second one - see that
/// RPC's own doc). With a `limits` entry above `1` (see `ClusterResourceLimit`'s own doc), more than
/// one distinct namespace can hold the *same* `ClusterResource` at once, so there can be more
/// entries here than there are `ClusterResource` values.
/// See `ClusterResources.conductor_state`.
class ClusterConductorState extends $pb.GeneratedMessage {
  factory ClusterConductorState({
    $core.Iterable<ClusterResourceLock>? locks,
    $core.Iterable<ClusterResourceLimit>? limits,
  }) {
    final $result = create();
    if (locks != null) {
      $result.locks.addAll(locks);
    }
    if (limits != null) {
      $result.limits.addAll(limits);
    }
    return $result;
  }
  ClusterConductorState._() : super();
  factory ClusterConductorState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClusterConductorState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClusterConductorState', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<ClusterResourceLock>(1, _omitFieldNames ? '' : 'locks', $pb.PbFieldType.PM, subBuilder: ClusterResourceLock.create)
    ..pc<ClusterResourceLimit>(2, _omitFieldNames ? '' : 'limits', $pb.PbFieldType.PM, subBuilder: ClusterResourceLimit.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClusterConductorState clone() => ClusterConductorState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClusterConductorState copyWith(void Function(ClusterConductorState) updates) => super.copyWith((message) => updates(message as ClusterConductorState)) as ClusterConductorState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClusterConductorState create() => ClusterConductorState._();
  ClusterConductorState createEmptyInstance() => create();
  static $pb.PbList<ClusterConductorState> createRepeated() => $pb.PbList<ClusterConductorState>();
  @$core.pragma('dart2js:noInline')
  static ClusterConductorState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClusterConductorState>(create);
  static ClusterConductorState? _defaultInstance;

  /// Locks currently held by the conductor.
  /// Mutations are only made by `FreeClusterResource` and `LockClusterResource`, not `ConfigureServer`.
  /// Changes to locks do *not* produce a new ServerConfiguration version.
  @$pb.TagNumber(1)
  $core.List<ClusterResourceLock> get locks => $_getList(0);

  /// How many distinct namespaces may concurrently hold each `ClusterResource`'s lock - e.g. only
  /// one headless browser at a time, but a handful of `ffmpeg`/ImageMagick conversions in parallel
  /// across the cluster, since those are far lighter-weight. Any `ClusterResource` not present here
  /// - including on a cluster that's never had `ConfigureServer` touch `limits` at all - defaults
  /// to `1` (see `ClusterTab.elm`'s matching client-side default, shown/edited there as "Browser
  /// Instance Limit"/"FFMPEG Process Limit"/"ImageMagick Process Limit"). These are changed by
  /// `ConfigureServer` (gated on `EDIT_CLUSTER_SETTINGS`, like the rest of `cluster_resources`) and
  /// create a new ServerConfiguration version, unlike `locks` above.
  @$pb.TagNumber(2)
  $core.List<ClusterResourceLimit> get limits => $_getList(1);
}

/// One namespace's currently-held lock on one or more `ClusterResource`s, and when it acquired
/// them - shown in `ClusterTab`'s Elm UI so an admin can tell a genuinely stuck lock (acquired
/// long ago, its holder's job surely long dead) from one just in normal, brief use, and reach for
/// `free_all_cluster_resources` (a `bin/` admin tool - see its own doc) accordingly.
class ClusterResourceLock extends $pb.GeneratedMessage {
  factory ClusterResourceLock({
    $core.String? lockHolderNamespaceId,
    $core.Iterable<ClusterResource>? resources,
    $13.Timestamp? acquiredAt,
  }) {
    final $result = create();
    if (lockHolderNamespaceId != null) {
      $result.lockHolderNamespaceId = lockHolderNamespaceId;
    }
    if (resources != null) {
      $result.resources.addAll(resources);
    }
    if (acquiredAt != null) {
      $result.acquiredAt = acquiredAt;
    }
    return $result;
  }
  ClusterResourceLock._() : super();
  factory ClusterResourceLock.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClusterResourceLock.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClusterResourceLock', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'lockHolderNamespaceId')
    ..pc<ClusterResource>(2, _omitFieldNames ? '' : 'resources', $pb.PbFieldType.KE, valueOf: ClusterResource.valueOf, enumValues: ClusterResource.values, defaultEnumValue: ClusterResource.CLUSTER_RESOURCE_BROWSER)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'acquiredAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClusterResourceLock clone() => ClusterResourceLock()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClusterResourceLock copyWith(void Function(ClusterResourceLock) updates) => super.copyWith((message) => updates(message as ClusterResourceLock)) as ClusterResourceLock;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClusterResourceLock create() => ClusterResourceLock._();
  ClusterResourceLock createEmptyInstance() => create();
  static $pb.PbList<ClusterResourceLock> createRepeated() => $pb.PbList<ClusterResourceLock>();
  @$core.pragma('dart2js:noInline')
  static ClusterResourceLock getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClusterResourceLock>(create);
  static ClusterResourceLock? _defaultInstance;

  /// The `namespace_id` (see `ClusterResources.namespace_id`) holding this lock.
  @$pb.TagNumber(1)
  $core.String get lockHolderNamespaceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set lockHolderNamespaceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLockHolderNamespaceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLockHolderNamespaceId() => clearField(1);

  /// Which resources this lock covers.
  @$pb.TagNumber(2)
  $core.List<ClusterResource> get resources => $_getList(1);

  /// When `LockClusterResources` granted this lock.
  @$pb.TagNumber(20)
  $13.Timestamp get acquiredAt => $_getN(2);
  @$pb.TagNumber(20)
  set acquiredAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasAcquiredAt() => $_has(2);
  @$pb.TagNumber(20)
  void clearAcquiredAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureAcquiredAt() => $_ensure(2);
}

/// One `ClusterResource`'s configured concurrency limit - a single `resource`/`limit` pairing per
/// message (both fields are singleton lists in practice; see `ClusterConductorState.limits`'s own
/// doc for why a `ClusterResource` missing from every `ClusterResourceLimit` here defaults to `1`
/// rather than `0`).
class ClusterResourceLimit extends $pb.GeneratedMessage {
  factory ClusterResourceLimit({
    $core.Iterable<ClusterResource>? resource,
    $core.Iterable<$core.int>? limit,
  }) {
    final $result = create();
    if (resource != null) {
      $result.resource.addAll(resource);
    }
    if (limit != null) {
      $result.limit.addAll(limit);
    }
    return $result;
  }
  ClusterResourceLimit._() : super();
  factory ClusterResourceLimit.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClusterResourceLimit.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClusterResourceLimit', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<ClusterResource>(1, _omitFieldNames ? '' : 'resource', $pb.PbFieldType.KE, valueOf: ClusterResource.valueOf, enumValues: ClusterResource.values, defaultEnumValue: ClusterResource.CLUSTER_RESOURCE_BROWSER)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClusterResourceLimit clone() => ClusterResourceLimit()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClusterResourceLimit copyWith(void Function(ClusterResourceLimit) updates) => super.copyWith((message) => updates(message as ClusterResourceLimit)) as ClusterResourceLimit;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClusterResourceLimit create() => ClusterResourceLimit._();
  ClusterResourceLimit createEmptyInstance() => create();
  static $pb.PbList<ClusterResourceLimit> createRepeated() => $pb.PbList<ClusterResourceLimit>();
  @$core.pragma('dart2js:noInline')
  static ClusterResourceLimit getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClusterResourceLimit>(create);
  static ClusterResourceLimit? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ClusterResource> get resource => $_getList(0);

  /// The number of distinct namespaces that may concurrently hold a lock on `resource`.
  @$pb.TagNumber(2)
  $core.List<$core.int> get limit => $_getList(1);
}

/// See [`LockClusterResources`](#grpc-api-LockClusterResources).
class LockClusterResourcesRequest extends $pb.GeneratedMessage {
  factory LockClusterResourcesRequest({
    $core.String? namespaceId,
    $core.Iterable<ClusterResource>? resources,
  }) {
    final $result = create();
    if (namespaceId != null) {
      $result.namespaceId = namespaceId;
    }
    if (resources != null) {
      $result.resources.addAll(resources);
    }
    return $result;
  }
  LockClusterResourcesRequest._() : super();
  factory LockClusterResourcesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LockClusterResourcesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LockClusterResourcesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'namespaceId')
    ..pc<ClusterResource>(2, _omitFieldNames ? '' : 'resources', $pb.PbFieldType.KE, valueOf: ClusterResource.valueOf, enumValues: ClusterResource.values, defaultEnumValue: ClusterResource.CLUSTER_RESOURCE_BROWSER)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LockClusterResourcesRequest clone() => LockClusterResourcesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LockClusterResourcesRequest copyWith(void Function(LockClusterResourcesRequest) updates) => super.copyWith((message) => updates(message as LockClusterResourcesRequest)) as LockClusterResourcesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LockClusterResourcesRequest create() => LockClusterResourcesRequest._();
  LockClusterResourcesRequest createEmptyInstance() => create();
  static $pb.PbList<LockClusterResourcesRequest> createRepeated() => $pb.PbList<LockClusterResourcesRequest>();
  @$core.pragma('dart2js:noInline')
  static LockClusterResourcesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LockClusterResourcesRequest>(create);
  static LockClusterResourcesRequest? _defaultInstance;

  /// This instance's own `ClusterResources.namespace_id`.
  @$pb.TagNumber(1)
  $core.String get namespaceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set namespaceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNamespaceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNamespaceId() => clearField(1);

  /// Which resources to lock - see the `ClusterResource` enum for what exists.
  @$pb.TagNumber(2)
  $core.List<ClusterResource> get resources => $_getList(1);
}

/// See [`LockClusterResources`](#grpc-api-LockClusterResources).
class LockClusterResourcesResponse extends $pb.GeneratedMessage {
  factory LockClusterResourcesResponse({
    $core.bool? granted,
    $core.String? holder,
  }) {
    final $result = create();
    if (granted != null) {
      $result.granted = granted;
    }
    if (holder != null) {
      $result.holder = holder;
    }
    return $result;
  }
  LockClusterResourcesResponse._() : super();
  factory LockClusterResourcesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LockClusterResourcesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LockClusterResourcesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'granted')
    ..aOS(2, _omitFieldNames ? '' : 'holder')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LockClusterResourcesResponse clone() => LockClusterResourcesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LockClusterResourcesResponse copyWith(void Function(LockClusterResourcesResponse) updates) => super.copyWith((message) => updates(message as LockClusterResourcesResponse)) as LockClusterResourcesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LockClusterResourcesResponse create() => LockClusterResourcesResponse._();
  LockClusterResourcesResponse createEmptyInstance() => create();
  static $pb.PbList<LockClusterResourcesResponse> createRepeated() => $pb.PbList<LockClusterResourcesResponse>();
  @$core.pragma('dart2js:noInline')
  static LockClusterResourcesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LockClusterResourcesResponse>(create);
  static LockClusterResourcesResponse? _defaultInstance;

  /// Whether every requested resource was successfully locked for `namespace_id`. `false` means
  /// none were locked (never a partial grant) - at least one of them is already held, by
  /// namespaces other than this one, by as many distinct holders as its configured
  /// `ClusterResourceLimit` allows (see that message's own doc); see `holder`. There's no
  /// server-side wait/queueing: a caller that gets `false` should back off and call
  /// `LockClusterResources` again later.
  @$pb.TagNumber(1)
  $core.bool get granted => $_getBF(0);
  @$pb.TagNumber(1)
  set granted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGranted() => $_has(0);
  @$pb.TagNumber(1)
  void clearGranted() => clearField(1);

  /// Set only when `granted` is `false`: one of the namespaces already holding a requested (and
  /// therefore denied) resource.
  @$pb.TagNumber(2)
  $core.String get holder => $_getSZ(1);
  @$pb.TagNumber(2)
  set holder($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHolder() => $_has(1);
  @$pb.TagNumber(2)
  void clearHolder() => clearField(2);
}

/// Releases resources this `namespace_id` previously locked via
/// [`LockClusterResources`](#grpc-api-LockClusterResources). A no-op (not an error) for any
/// resource `namespace_id` doesn't currently hold - e.g. safe to call unconditionally during
/// cleanup even if the matching lock attempt itself failed or was never confirmed.
class FreeClusterResourcesRequest extends $pb.GeneratedMessage {
  factory FreeClusterResourcesRequest({
    $core.String? namespaceId,
    $core.Iterable<ClusterResource>? resources,
  }) {
    final $result = create();
    if (namespaceId != null) {
      $result.namespaceId = namespaceId;
    }
    if (resources != null) {
      $result.resources.addAll(resources);
    }
    return $result;
  }
  FreeClusterResourcesRequest._() : super();
  factory FreeClusterResourcesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FreeClusterResourcesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FreeClusterResourcesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'namespaceId')
    ..pc<ClusterResource>(2, _omitFieldNames ? '' : 'resources', $pb.PbFieldType.KE, valueOf: ClusterResource.valueOf, enumValues: ClusterResource.values, defaultEnumValue: ClusterResource.CLUSTER_RESOURCE_BROWSER)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FreeClusterResourcesRequest clone() => FreeClusterResourcesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FreeClusterResourcesRequest copyWith(void Function(FreeClusterResourcesRequest) updates) => super.copyWith((message) => updates(message as FreeClusterResourcesRequest)) as FreeClusterResourcesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FreeClusterResourcesRequest create() => FreeClusterResourcesRequest._();
  FreeClusterResourcesRequest createEmptyInstance() => create();
  static $pb.PbList<FreeClusterResourcesRequest> createRepeated() => $pb.PbList<FreeClusterResourcesRequest>();
  @$core.pragma('dart2js:noInline')
  static FreeClusterResourcesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FreeClusterResourcesRequest>(create);
  static FreeClusterResourcesRequest? _defaultInstance;

  /// This instance's own `ClusterResources.namespace_id` - must match whichever `namespace_id`
  /// is recorded as the current holder for a resource to actually be released.
  @$pb.TagNumber(1)
  $core.String get namespaceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set namespaceId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNamespaceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNamespaceId() => clearField(1);

  /// Which resources to release.
  @$pb.TagNumber(2)
  $core.List<ClusterResource> get resources => $_getList(1);
}

/// Useful for setting your Rellm instance up to run underneath a CDN.
/// By default, the web client uses `window.location.hostname` to determine the backend server.
/// If set, the web client will use this value instead. NOTE: Only applies to Tamagui web client for now.
class ExternalCDNConfig extends $pb.GeneratedMessage {
  factory ExternalCDNConfig({
    $core.String? frontendHost,
    $core.String? backendHost,
    $core.bool? secureMedia,
    $core.String? mediaIpv4Allowlist,
    $core.String? mediaIpv6Allowlist,
    $core.bool? cdnGrpc,
  }) {
    final $result = create();
    if (frontendHost != null) {
      $result.frontendHost = frontendHost;
    }
    if (backendHost != null) {
      $result.backendHost = backendHost;
    }
    if (secureMedia != null) {
      $result.secureMedia = secureMedia;
    }
    if (mediaIpv4Allowlist != null) {
      $result.mediaIpv4Allowlist = mediaIpv4Allowlist;
    }
    if (mediaIpv6Allowlist != null) {
      $result.mediaIpv6Allowlist = mediaIpv6Allowlist;
    }
    if (cdnGrpc != null) {
      $result.cdnGrpc = cdnGrpc;
    }
    return $result;
  }
  ExternalCDNConfig._() : super();
  factory ExternalCDNConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExternalCDNConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExternalCDNConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'frontendHost')
    ..aOS(2, _omitFieldNames ? '' : 'backendHost')
    ..aOB(3, _omitFieldNames ? '' : 'secureMedia')
    ..aOS(4, _omitFieldNames ? '' : 'mediaIpv4Allowlist')
    ..aOS(5, _omitFieldNames ? '' : 'mediaIpv6Allowlist')
    ..aOB(6, _omitFieldNames ? '' : 'cdnGrpc')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExternalCDNConfig clone() => ExternalCDNConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExternalCDNConfig copyWith(void Function(ExternalCDNConfig) updates) => super.copyWith((message) => updates(message as ExternalCDNConfig)) as ExternalCDNConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExternalCDNConfig create() => ExternalCDNConfig._();
  ExternalCDNConfig createEmptyInstance() => create();
  static $pb.PbList<ExternalCDNConfig> createRepeated() => $pb.PbList<ExternalCDNConfig>();
  @$core.pragma('dart2js:noInline')
  static ExternalCDNConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExternalCDNConfig>(create);
  static ExternalCDNConfig? _defaultInstance;

  /// The domain where the frontend is hosted. For example, jonline.io. Typically
  /// your CDN (like Cloudflare) should own the DNS for this domain.
  @$pb.TagNumber(1)
  $core.String get frontendHost => $_getSZ(0);
  @$pb.TagNumber(1)
  set frontendHost($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFrontendHost() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrontendHost() => clearField(1);

  /// The domain where the backend is hosted. For example, jonline.io.itsj.online.
  /// Typically your Kubernetes provider should own DNS for this domain.
  @$pb.TagNumber(2)
  $core.String get backendHost => $_getSZ(1);
  @$pb.TagNumber(2)
  set backendHost($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasBackendHost() => $_has(1);
  @$pb.TagNumber(2)
  void clearBackendHost() => clearField(2);

  /// (TODO) When set, the HTTP `GET /media/<id>?<authorization>` endpoint will be disabled by default on the
  /// HTTP (non-secure) server that sends data to the CDN. Only requests from IPs in
  /// `media_ipv4_allowlist` and `media_ipv6_allowlist` will be allowed.
  @$pb.TagNumber(3)
  $core.bool get secureMedia => $_getBF(2);
  @$pb.TagNumber(3)
  set secureMedia($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSecureMedia() => $_has(2);
  @$pb.TagNumber(3)
  void clearSecureMedia() => clearField(3);

  /// Whitespace- and/or comma- separated list of IPv4 addresses/ranges
  /// to whom media data may be served. Only applicable if `secure_media` is `true`.
  /// For reference, Cloudflare's are at https://www.cloudflare.com/ips-v4.
  @$pb.TagNumber(4)
  $core.String get mediaIpv4Allowlist => $_getSZ(3);
  @$pb.TagNumber(4)
  set mediaIpv4Allowlist($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMediaIpv4Allowlist() => $_has(3);
  @$pb.TagNumber(4)
  void clearMediaIpv4Allowlist() => clearField(4);

  /// Whitespace- and/or comma- separated list of IPv6 addresses/ranges
  /// to whom media data may be served. Only applicable if `secure_media` is `true`.
  /// For reference, Cloudflare's are at https://www.cloudflare.com/ips-v6.
  @$pb.TagNumber(5)
  $core.String get mediaIpv6Allowlist => $_getSZ(4);
  @$pb.TagNumber(5)
  set mediaIpv6Allowlist($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMediaIpv6Allowlist() => $_has(4);
  @$pb.TagNumber(5)
  void clearMediaIpv6Allowlist() => clearField(5);

  /// (TODO) When implemented, this actually changes the whole Rellm protocol (in terms of ports).
  /// When enabled, Rellm should *not* server a secure site on HTTPS, and instead serve
  /// the Tonic gRPC server there (on port 443). Jonine clients will need to be updated to
  /// always seek out a secure client on port 443 when this feature is enabled.
  /// This would let Rellm leverage Cloudflare's DDOS protection and performance on gRPC as well as HTTP.
  /// (This is a Cloudflare-specific feature requirement.)
  @$pb.TagNumber(6)
  $core.bool get cdnGrpc => $_getBF(5);
  @$pb.TagNumber(6)
  set cdnGrpc($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCdnGrpc() => $_has(5);
  @$pb.TagNumber(6)
  void clearCdnGrpc() => clearField(6);
}

/// Media is a special type and less customizable than "Features."
class MediaSettings extends $pb.GeneratedMessage {
  factory MediaSettings({
    $core.bool? visible,
    $14.Moderation? defaultModeration,
    $14.Visibility? defaultVisibility,
    $fixnum.Int64? defaultMediaAllocationBytes,
  }) {
    final $result = create();
    if (visible != null) {
      $result.visible = visible;
    }
    if (defaultModeration != null) {
      $result.defaultModeration = defaultModeration;
    }
    if (defaultVisibility != null) {
      $result.defaultVisibility = defaultVisibility;
    }
    if (defaultMediaAllocationBytes != null) {
      $result.defaultMediaAllocationBytes = defaultMediaAllocationBytes;
    }
    return $result;
  }
  MediaSettings._() : super();
  factory MediaSettings.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaSettings.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaSettings', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'visible')
    ..e<$14.Moderation>(2, _omitFieldNames ? '' : 'defaultModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Visibility>(3, _omitFieldNames ? '' : 'defaultVisibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'defaultMediaAllocationBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaSettings clone() => MediaSettings()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaSettings copyWith(void Function(MediaSettings) updates) => super.copyWith((message) => updates(message as MediaSettings)) as MediaSettings;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaSettings create() => MediaSettings._();
  MediaSettings createEmptyInstance() => create();
  static $pb.PbList<MediaSettings> createRepeated() => $pb.PbList<MediaSettings>();
  @$core.pragma('dart2js:noInline')
  static MediaSettings getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaSettings>(create);
  static MediaSettings? _defaultInstance;

  /// Hide the Posts or Events tab from the user with this flag.
  @$pb.TagNumber(1)
  $core.bool get visible => $_getBF(0);
  @$pb.TagNumber(1)
  set visible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVisible() => $_has(0);
  @$pb.TagNumber(1)
  void clearVisible() => clearField(1);

  /// Only `UNMODERATED` and `PENDING` are valid.
  /// When `UNMODERATED`, user reports may transition status to `PENDING`.
  /// When `PENDING`, users' SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not
  /// be visible until a moderator approves them. `LIMITED` visiblity
  /// posts are always visible to targeted users (who have not blocked
  /// the author) regardless of default_moderation.
  @$pb.TagNumber(2)
  $14.Moderation get defaultModeration => $_getN(1);
  @$pb.TagNumber(2)
  set defaultModeration($14.Moderation v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDefaultModeration() => $_has(1);
  @$pb.TagNumber(2)
  void clearDefaultModeration() => clearField(2);

  /// Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid
  /// if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]`
  /// as appropriate.
  @$pb.TagNumber(3)
  $14.Visibility get defaultVisibility => $_getN(2);
  @$pb.TagNumber(3)
  set defaultVisibility($14.Visibility v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasDefaultVisibility() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultVisibility() => clearField(3);

  /// Default media storage allocation for newly created users. Defaults to 10MB.
  @$pb.TagNumber(4)
  $fixnum.Int64 get defaultMediaAllocationBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set defaultMediaAllocationBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDefaultMediaAllocationBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearDefaultMediaAllocationBytes() => clearField(4);
}

/// Whether this server's `/market` is open -- an explicit, admin-set toggle independent of
/// `StripeConfig.stripe_enabled` (an admin can configure Stripe credentials without opening the
/// storefront yet, or temporarily close it without touching those credentials). See
/// `ServerConfiguration.market_settings`'s own doc on why this lives outside `StripeConfig`: it's
/// the one bit that has to stay visible to non-admins for federated multi-server Market browsing to
/// work at all.
class MarketSettings extends $pb.GeneratedMessage {
  factory MarketSettings({
    $core.bool? enabled,
    $core.bool? stripeConfigured,
  }) {
    final $result = create();
    if (enabled != null) {
      $result.enabled = enabled;
    }
    if (stripeConfigured != null) {
      $result.stripeConfigured = stripeConfigured;
    }
    return $result;
  }
  MarketSettings._() : super();
  factory MarketSettings.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketSettings.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketSettings', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..aOB(2, _omitFieldNames ? '' : 'stripeConfigured')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketSettings clone() => MarketSettings()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketSettings copyWith(void Function(MarketSettings) updates) => super.copyWith((message) => updates(message as MarketSettings)) as MarketSettings;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketSettings create() => MarketSettings._();
  MarketSettings createEmptyInstance() => create();
  static $pb.PbList<MarketSettings> createRepeated() => $pb.PbList<MarketSettings>();
  @$core.pragma('dart2js:noInline')
  static MarketSettings getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketSettings>(create);
  static MarketSettings? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => clearField(1);

  /// Whether Stripe is actually usable right now -- `stripe_config.stripe_enabled` is true AND a
  /// `stripe_secret_key` is on file. Computed live on every `GetServerConfiguration` (never read back
  /// from whatever was last saved to `market_settings` itself), and -- like `enabled` above --
  /// deliberately never stripped for non-admins: it's the public "can I actually buy something here"
  /// signal a buyer needs (e.g. to grey out `/market/product/:id`'s "Buy" button with a
  /// "Stripe is not configured" message) without ever exposing `StripeConfig` itself, which stays
  /// admin-only.
  @$pb.TagNumber(2)
  $core.bool get stripeConfigured => $_getBF(1);
  @$pb.TagNumber(2)
  set stripeConfigured($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStripeConfigured() => $_has(1);
  @$pb.TagNumber(2)
  void clearStripeConfigured() => clearField(2);
}

/// Settings for a feature (e.g. People, Groups, Posts, Events, Media).
/// Encompasses both the feature's visibility and moderation settings.
class FeatureSettings extends $pb.GeneratedMessage {
  factory FeatureSettings({
    $core.bool? visible,
    $14.Moderation? defaultModeration,
    $14.Visibility? defaultVisibility,
    $core.String? aliasSingular,
    $core.String? aliasPlural,
  }) {
    final $result = create();
    if (visible != null) {
      $result.visible = visible;
    }
    if (defaultModeration != null) {
      $result.defaultModeration = defaultModeration;
    }
    if (defaultVisibility != null) {
      $result.defaultVisibility = defaultVisibility;
    }
    if (aliasSingular != null) {
      $result.aliasSingular = aliasSingular;
    }
    if (aliasPlural != null) {
      $result.aliasPlural = aliasPlural;
    }
    return $result;
  }
  FeatureSettings._() : super();
  factory FeatureSettings.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FeatureSettings.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FeatureSettings', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'visible')
    ..e<$14.Moderation>(2, _omitFieldNames ? '' : 'defaultModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Visibility>(3, _omitFieldNames ? '' : 'defaultVisibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..aOS(4, _omitFieldNames ? '' : 'aliasSingular')
    ..aOS(5, _omitFieldNames ? '' : 'aliasPlural')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FeatureSettings clone() => FeatureSettings()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FeatureSettings copyWith(void Function(FeatureSettings) updates) => super.copyWith((message) => updates(message as FeatureSettings)) as FeatureSettings;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FeatureSettings create() => FeatureSettings._();
  FeatureSettings createEmptyInstance() => create();
  static $pb.PbList<FeatureSettings> createRepeated() => $pb.PbList<FeatureSettings>();
  @$core.pragma('dart2js:noInline')
  static FeatureSettings getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FeatureSettings>(create);
  static FeatureSettings? _defaultInstance;

  /// Hide the Posts or Events tab from the user with this flag.
  @$pb.TagNumber(1)
  $core.bool get visible => $_getBF(0);
  @$pb.TagNumber(1)
  set visible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVisible() => $_has(0);
  @$pb.TagNumber(1)
  void clearVisible() => clearField(1);

  /// Only `UNMODERATED` and `PENDING` are valid.
  /// When `UNMODERATED`, user reports may transition status to `PENDING`.
  /// When `PENDING`, users' SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not
  /// be visible until a moderator approves them. `LIMITED` visiblity
  /// posts are always visible to targeted users (who have not blocked
  /// the author) regardless of default_moderation.
  @$pb.TagNumber(2)
  $14.Moderation get defaultModeration => $_getN(1);
  @$pb.TagNumber(2)
  set defaultModeration($14.Moderation v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDefaultModeration() => $_has(1);
  @$pb.TagNumber(2)
  void clearDefaultModeration() => clearField(2);

  /// Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid
  /// if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]`
  /// as appropriate.
  @$pb.TagNumber(3)
  $14.Visibility get defaultVisibility => $_getN(2);
  @$pb.TagNumber(3)
  set defaultVisibility($14.Visibility v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasDefaultVisibility() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultVisibility() => clearField(3);

  /// Can be used to rename, e.g., "Person" to "Contributor" or "Group" to "Community"
  @$pb.TagNumber(4)
  $core.String get aliasSingular => $_getSZ(3);
  @$pb.TagNumber(4)
  set aliasSingular($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAliasSingular() => $_has(3);
  @$pb.TagNumber(4)
  void clearAliasSingular() => clearField(4);

  /// Can be used to rename, e.g. "Groups" to "Subtwaddits" or "People" to "Folks"
  @$pb.TagNumber(5)
  $core.String get aliasPlural => $_getSZ(4);
  @$pb.TagNumber(5)
  set aliasPlural($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAliasPlural() => $_has(4);
  @$pb.TagNumber(5)
  void clearAliasPlural() => clearField(5);
}

/// Specific settings for Posts.
class PostSettings extends $pb.GeneratedMessage {
  factory PostSettings({
    $core.bool? visible,
    $14.Moderation? defaultModeration,
    $14.Visibility? defaultVisibility,
    $core.String? aliasSingular,
    $core.String? aliasPlural,
    $core.bool? enableReplies,
  }) {
    final $result = create();
    if (visible != null) {
      $result.visible = visible;
    }
    if (defaultModeration != null) {
      $result.defaultModeration = defaultModeration;
    }
    if (defaultVisibility != null) {
      $result.defaultVisibility = defaultVisibility;
    }
    if (aliasSingular != null) {
      $result.aliasSingular = aliasSingular;
    }
    if (aliasPlural != null) {
      $result.aliasPlural = aliasPlural;
    }
    if (enableReplies != null) {
      $result.enableReplies = enableReplies;
    }
    return $result;
  }
  PostSettings._() : super();
  factory PostSettings.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PostSettings.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PostSettings', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'visible')
    ..e<$14.Moderation>(2, _omitFieldNames ? '' : 'defaultModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Visibility>(3, _omitFieldNames ? '' : 'defaultVisibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..aOS(4, _omitFieldNames ? '' : 'aliasSingular')
    ..aOS(5, _omitFieldNames ? '' : 'aliasPlural')
    ..aOB(6, _omitFieldNames ? '' : 'enableReplies')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PostSettings clone() => PostSettings()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PostSettings copyWith(void Function(PostSettings) updates) => super.copyWith((message) => updates(message as PostSettings)) as PostSettings;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PostSettings create() => PostSettings._();
  PostSettings createEmptyInstance() => create();
  static $pb.PbList<PostSettings> createRepeated() => $pb.PbList<PostSettings>();
  @$core.pragma('dart2js:noInline')
  static PostSettings getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PostSettings>(create);
  static PostSettings? _defaultInstance;

  /// Hide the Posts tab from the user with this flag.
  @$pb.TagNumber(1)
  $core.bool get visible => $_getBF(0);
  @$pb.TagNumber(1)
  set visible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVisible() => $_has(0);
  @$pb.TagNumber(1)
  void clearVisible() => clearField(1);

  /// Only `UNMODERATED` and `PENDING` are valid.
  /// When `UNMODERATED`, user reports may transition status to `PENDING`.
  /// When `PENDING`, users' SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not
  /// be visible until a moderator approves them. `LIMITED` visiblity
  /// posts are always visible to targeted users (who have not blocked
  /// the author) regardless of default_moderation.
  @$pb.TagNumber(2)
  $14.Moderation get defaultModeration => $_getN(1);
  @$pb.TagNumber(2)
  set defaultModeration($14.Moderation v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDefaultModeration() => $_has(1);
  @$pb.TagNumber(2)
  void clearDefaultModeration() => clearField(2);

  /// Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid
  /// if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]`
  /// as appropriate.
  @$pb.TagNumber(3)
  $14.Visibility get defaultVisibility => $_getN(2);
  @$pb.TagNumber(3)
  set defaultVisibility($14.Visibility v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasDefaultVisibility() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultVisibility() => clearField(3);

  /// Can be used to rename, e.g., "Post" "Highlight" or "Squirt"
  @$pb.TagNumber(4)
  $core.String get aliasSingular => $_getSZ(3);
  @$pb.TagNumber(4)
  set aliasSingular($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAliasSingular() => $_has(3);
  @$pb.TagNumber(4)
  void clearAliasSingular() => clearField(4);

  /// Can be used to rename, e.g. "Posts" to "Splurts" or "Memories"
  @$pb.TagNumber(5)
  $core.String get aliasPlural => $_getSZ(4);
  @$pb.TagNumber(5)
  set aliasPlural($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAliasPlural() => $_has(4);
  @$pb.TagNumber(5)
  void clearAliasPlural() => clearField(5);

  /// Controls whether replies are shown in the UI. Note that users' ability to reply
  /// is controlled by the `REPLY_TO_POSTS` permission.
  @$pb.TagNumber(6)
  $core.bool get enableReplies => $_getBF(5);
  @$pb.TagNumber(6)
  set enableReplies($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnableReplies() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableReplies() => clearField(6);
}

/// Specific settings for Events.
class EventSettings extends $pb.GeneratedMessage {
  factory EventSettings({
    $core.bool? visible,
    $14.Moderation? defaultModeration,
    $14.Visibility? defaultVisibility,
    $core.String? aliasSingular,
    $core.String? aliasPlural,
    $core.bool? enableReplies,
    $core.int? calendarLookbackDays,
    CalendarDisplayMode? defaultCalendarDisplayMode,
    $core.bool? showStartedOrLongEventsByDefault,
  }) {
    final $result = create();
    if (visible != null) {
      $result.visible = visible;
    }
    if (defaultModeration != null) {
      $result.defaultModeration = defaultModeration;
    }
    if (defaultVisibility != null) {
      $result.defaultVisibility = defaultVisibility;
    }
    if (aliasSingular != null) {
      $result.aliasSingular = aliasSingular;
    }
    if (aliasPlural != null) {
      $result.aliasPlural = aliasPlural;
    }
    if (enableReplies != null) {
      $result.enableReplies = enableReplies;
    }
    if (calendarLookbackDays != null) {
      $result.calendarLookbackDays = calendarLookbackDays;
    }
    if (defaultCalendarDisplayMode != null) {
      $result.defaultCalendarDisplayMode = defaultCalendarDisplayMode;
    }
    if (showStartedOrLongEventsByDefault != null) {
      $result.showStartedOrLongEventsByDefault = showStartedOrLongEventsByDefault;
    }
    return $result;
  }
  EventSettings._() : super();
  factory EventSettings.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EventSettings.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EventSettings', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'visible')
    ..e<$14.Moderation>(2, _omitFieldNames ? '' : 'defaultModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Visibility>(3, _omitFieldNames ? '' : 'defaultVisibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..aOS(4, _omitFieldNames ? '' : 'aliasSingular')
    ..aOS(5, _omitFieldNames ? '' : 'aliasPlural')
    ..aOB(6, _omitFieldNames ? '' : 'enableReplies')
    ..a<$core.int>(7, _omitFieldNames ? '' : 'calendarLookbackDays', $pb.PbFieldType.OU3)
    ..e<CalendarDisplayMode>(8, _omitFieldNames ? '' : 'defaultCalendarDisplayMode', $pb.PbFieldType.OE, defaultOrMaker: CalendarDisplayMode.CALENDAR_DISPLAY_WEEK, valueOf: CalendarDisplayMode.valueOf, enumValues: CalendarDisplayMode.values)
    ..aOB(9, _omitFieldNames ? '' : 'showStartedOrLongEventsByDefault')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EventSettings clone() => EventSettings()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EventSettings copyWith(void Function(EventSettings) updates) => super.copyWith((message) => updates(message as EventSettings)) as EventSettings;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventSettings create() => EventSettings._();
  EventSettings createEmptyInstance() => create();
  static $pb.PbList<EventSettings> createRepeated() => $pb.PbList<EventSettings>();
  @$core.pragma('dart2js:noInline')
  static EventSettings getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EventSettings>(create);
  static EventSettings? _defaultInstance;

  /// Hide the Events tab from the user with this flag.
  @$pb.TagNumber(1)
  $core.bool get visible => $_getBF(0);
  @$pb.TagNumber(1)
  set visible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVisible() => $_has(0);
  @$pb.TagNumber(1)
  void clearVisible() => clearField(1);

  /// Only `UNMODERATED` and `PENDING` are valid.
  /// When `UNMODERATED`, user reports may transition status to `PENDING`.
  /// When `PENDING`, users' SERVER_PUBLIC or `GLOBAL_PUBLIC` posts will not
  /// be visible until a moderator approves them. `LIMITED` visiblity
  /// posts are always visible to targeted users (who have not blocked
  /// the author) regardless of default_moderation.
  @$pb.TagNumber(2)
  $14.Moderation get defaultModeration => $_getN(1);
  @$pb.TagNumber(2)
  set defaultModeration($14.Moderation v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDefaultModeration() => $_has(1);
  @$pb.TagNumber(2)
  void clearDefaultModeration() => clearField(2);

  /// Only `SERVER_PUBLIC` and `GLOBAL_PUBLIC` are valid. `GLOBAL_PUBLIC` is only valid
  /// if default_user_permissions contains `GLOBALLY_PUBLISH_[USERS|GROUPS|POSTS|EVENTS]`
  /// as appropriate.
  @$pb.TagNumber(3)
  $14.Visibility get defaultVisibility => $_getN(2);
  @$pb.TagNumber(3)
  set defaultVisibility($14.Visibility v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasDefaultVisibility() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultVisibility() => clearField(3);

  /// Can be used to rename, e.g., "Event" to "Gig" or "Performance"
  @$pb.TagNumber(4)
  $core.String get aliasSingular => $_getSZ(3);
  @$pb.TagNumber(4)
  set aliasSingular($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAliasSingular() => $_has(3);
  @$pb.TagNumber(4)
  void clearAliasSingular() => clearField(4);

  /// Can be used to rename, e.g. "Events" to "Show," "Game," "Competition"
  @$pb.TagNumber(5)
  $core.String get aliasPlural => $_getSZ(4);
  @$pb.TagNumber(5)
  set aliasPlural($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAliasPlural() => $_has(4);
  @$pb.TagNumber(5)
  void clearAliasPlural() => clearField(5);

  /// Works the same as for Posts.
  @$pb.TagNumber(6)
  $core.bool get enableReplies => $_getBF(5);
  @$pb.TagNumber(6)
  set enableReplies($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEnableReplies() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableReplies() => clearField(6);

  /// How far to look back for the "Upcoming Events" tab in the server's UI. Defaults to `14`.
  /// Servers with fewer events may want to set to a higher value.
  @$pb.TagNumber(7)
  $core.int get calendarLookbackDays => $_getIZ(6);
  @$pb.TagNumber(7)
  set calendarLookbackDays($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasCalendarLookbackDays() => $_has(6);
  @$pb.TagNumber(7)
  void clearCalendarLookbackDays() => clearField(7);

  /// What the Events Calendar's default UI mode will be. Defaults to `CALENDAR_DISPLAY_WEEK`.
  /// Servers with fewer events may want to set `CALENDAR_DISPLAY_MONTH`,
  /// or with more to `CALENDAR_DISPLAY_DAY`.
  @$pb.TagNumber(8)
  CalendarDisplayMode get defaultCalendarDisplayMode => $_getN(7);
  @$pb.TagNumber(8)
  set defaultCalendarDisplayMode(CalendarDisplayMode v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasDefaultCalendarDisplayMode() => $_has(7);
  @$pb.TagNumber(8)
  void clearDefaultCalendarDisplayMode() => clearField(8);

  ///  Affects the Elm UI "▽" button on EventsPages (embedded or no).
  ///  When this is false, that filter defaults to "on." When true, that filter
  ///  defaults to "off."
  ///
  ///  For a band site (where you want to show your "true calendar"), this is best set to `true`.
  ///  For a site where you have lots of event postings, it's best set to `false`.
  @$pb.TagNumber(9)
  $core.bool get showStartedOrLongEventsByDefault => $_getBF(8);
  @$pb.TagNumber(9)
  set showStartedOrLongEventsByDefault($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasShowStartedOrLongEventsByDefault() => $_has(8);
  @$pb.TagNumber(9)
  void clearShowStartedOrLongEventsByDefault() => clearField(9);
}

/// User-facing information about the server displayed on the "about" page.
class ServerInfo extends $pb.GeneratedMessage {
  factory ServerInfo({
    $core.String? name,
    $core.String? shortName,
    $core.String? description,
    $core.String? privacyPolicy,
    ServerLogo? logo,
    WebUserInterface? webUserInterface,
    ServerColors? colors,
    $core.String? mediaPolicy,
  @$core.Deprecated('This field is deprecated.')
    $core.Iterable<$core.String>? recommendedServerHosts,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (shortName != null) {
      $result.shortName = shortName;
    }
    if (description != null) {
      $result.description = description;
    }
    if (privacyPolicy != null) {
      $result.privacyPolicy = privacyPolicy;
    }
    if (logo != null) {
      $result.logo = logo;
    }
    if (webUserInterface != null) {
      $result.webUserInterface = webUserInterface;
    }
    if (colors != null) {
      $result.colors = colors;
    }
    if (mediaPolicy != null) {
      $result.mediaPolicy = mediaPolicy;
    }
    if (recommendedServerHosts != null) {
      // ignore: deprecated_member_use_from_same_package
      $result.recommendedServerHosts.addAll(recommendedServerHosts);
    }
    return $result;
  }
  ServerInfo._() : super();
  factory ServerInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ServerInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ServerInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'shortName')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'privacyPolicy')
    ..aOM<ServerLogo>(5, _omitFieldNames ? '' : 'logo', subBuilder: ServerLogo.create)
    ..e<WebUserInterface>(6, _omitFieldNames ? '' : 'webUserInterface', $pb.PbFieldType.OE, defaultOrMaker: WebUserInterface.FLUTTER_WEB, valueOf: WebUserInterface.valueOf, enumValues: WebUserInterface.values)
    ..aOM<ServerColors>(7, _omitFieldNames ? '' : 'colors', subBuilder: ServerColors.create)
    ..aOS(8, _omitFieldNames ? '' : 'mediaPolicy')
    ..pPS(9, _omitFieldNames ? '' : 'recommendedServerHosts')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ServerInfo clone() => ServerInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ServerInfo copyWith(void Function(ServerInfo) updates) => super.copyWith((message) => updates(message as ServerInfo)) as ServerInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerInfo create() => ServerInfo._();
  ServerInfo createEmptyInstance() => create();
  static $pb.PbList<ServerInfo> createRepeated() => $pb.PbList<ServerInfo>();
  @$core.pragma('dart2js:noInline')
  static ServerInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerInfo>(create);
  static ServerInfo? _defaultInstance;

  /// Name of the server.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// Short name of the server. Used in URLs, etc. (Currently unused.)
  @$pb.TagNumber(2)
  $core.String get shortName => $_getSZ(1);
  @$pb.TagNumber(2)
  set shortName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasShortName() => $_has(1);
  @$pb.TagNumber(2)
  void clearShortName() => clearField(2);

  /// Description of the server.
  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  /// The server's privacy policy. Will be displayed during account creation
  /// and on the `/about` page.
  @$pb.TagNumber(4)
  $core.String get privacyPolicy => $_getSZ(3);
  @$pb.TagNumber(4)
  set privacyPolicy($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPrivacyPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrivacyPolicy() => clearField(4);

  /// Multi-size logo data for the server.
  @$pb.TagNumber(5)
  ServerLogo get logo => $_getN(4);
  @$pb.TagNumber(5)
  set logo(ServerLogo v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasLogo() => $_has(4);
  @$pb.TagNumber(5)
  void clearLogo() => clearField(5);
  @$pb.TagNumber(5)
  ServerLogo ensureLogo() => $_ensure(4);

  /// The web UI to use (React/Tamagui (default) vs. Flutter Web)
  @$pb.TagNumber(6)
  WebUserInterface get webUserInterface => $_getN(5);
  @$pb.TagNumber(6)
  set webUserInterface(WebUserInterface v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasWebUserInterface() => $_has(5);
  @$pb.TagNumber(6)
  void clearWebUserInterface() => clearField(6);

  /// The color scheme for the server.
  @$pb.TagNumber(7)
  ServerColors get colors => $_getN(6);
  @$pb.TagNumber(7)
  set colors(ServerColors v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasColors() => $_has(6);
  @$pb.TagNumber(7)
  void clearColors() => clearField(7);
  @$pb.TagNumber(7)
  ServerColors ensureColors() => $_ensure(6);

  /// The media policy for the server. Will be displayed during account creation
  /// and on the `/about` page.
  @$pb.TagNumber(8)
  $core.String get mediaPolicy => $_getSZ(7);
  @$pb.TagNumber(8)
  set mediaPolicy($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasMediaPolicy() => $_has(7);
  @$pb.TagNumber(8)
  void clearMediaPolicy() => clearField(8);

  /// This will be replaced with FederationInfo soon.
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(9)
  $core.List<$core.String> get recommendedServerHosts => $_getList(8);
}

/// Logo data for the server. Built atop Rellm [`Media` APIs](#rellm-Media).
class ServerLogo extends $pb.GeneratedMessage {
  factory ServerLogo({
    $core.String? squareMediaId,
    $core.String? squareMediaIdDark,
    $core.String? wideMediaId,
    $core.String? wideMediaIdDark,
  }) {
    final $result = create();
    if (squareMediaId != null) {
      $result.squareMediaId = squareMediaId;
    }
    if (squareMediaIdDark != null) {
      $result.squareMediaIdDark = squareMediaIdDark;
    }
    if (wideMediaId != null) {
      $result.wideMediaId = wideMediaId;
    }
    if (wideMediaIdDark != null) {
      $result.wideMediaIdDark = wideMediaIdDark;
    }
    return $result;
  }
  ServerLogo._() : super();
  factory ServerLogo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ServerLogo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ServerLogo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'squareMediaId', protoName: 'squareMediaId')
    ..aOS(2, _omitFieldNames ? '' : 'squareMediaIdDark', protoName: 'squareMediaIdDark')
    ..aOS(3, _omitFieldNames ? '' : 'wideMediaId', protoName: 'wideMediaId')
    ..aOS(4, _omitFieldNames ? '' : 'wideMediaIdDark', protoName: 'wideMediaIdDark')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ServerLogo clone() => ServerLogo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ServerLogo copyWith(void Function(ServerLogo) updates) => super.copyWith((message) => updates(message as ServerLogo)) as ServerLogo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerLogo create() => ServerLogo._();
  ServerLogo createEmptyInstance() => create();
  static $pb.PbList<ServerLogo> createRepeated() => $pb.PbList<ServerLogo>();
  @$core.pragma('dart2js:noInline')
  static ServerLogo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerLogo>(create);
  static ServerLogo? _defaultInstance;

  /// The media ID for the square logo.
  @$pb.TagNumber(1)
  $core.String get squareMediaId => $_getSZ(0);
  @$pb.TagNumber(1)
  set squareMediaId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSquareMediaId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSquareMediaId() => clearField(1);

  /// The media ID for the square logo in dark mode.
  @$pb.TagNumber(2)
  $core.String get squareMediaIdDark => $_getSZ(1);
  @$pb.TagNumber(2)
  set squareMediaIdDark($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSquareMediaIdDark() => $_has(1);
  @$pb.TagNumber(2)
  void clearSquareMediaIdDark() => clearField(2);

  /// The media ID for the wide logo.
  @$pb.TagNumber(3)
  $core.String get wideMediaId => $_getSZ(2);
  @$pb.TagNumber(3)
  set wideMediaId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWideMediaId() => $_has(2);
  @$pb.TagNumber(3)
  void clearWideMediaId() => clearField(3);

  /// The media ID for the wide logo in dark mode.
  @$pb.TagNumber(4)
  $core.String get wideMediaIdDark => $_getSZ(3);
  @$pb.TagNumber(4)
  set wideMediaIdDark($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasWideMediaIdDark() => $_has(3);
  @$pb.TagNumber(4)
  void clearWideMediaIdDark() => clearField(4);
}

/// If set, overrides the default tab set for the Elm navigation on a Rellm instance.
class CustomNavigationTabSet extends $pb.GeneratedMessage {
  factory CustomNavigationTabSet({
    CustomHomePage? home,
    $core.Iterable<CustomNavigationTab>? tabs,
    NavigationTabStyle? tabStyle,
  }) {
    final $result = create();
    if (home != null) {
      $result.home = home;
    }
    if (tabs != null) {
      $result.tabs.addAll(tabs);
    }
    if (tabStyle != null) {
      $result.tabStyle = tabStyle;
    }
    return $result;
  }
  CustomNavigationTabSet._() : super();
  factory CustomNavigationTabSet.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CustomNavigationTabSet.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CustomNavigationTabSet', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<CustomHomePage>(1, _omitFieldNames ? '' : 'home', subBuilder: CustomHomePage.create)
    ..pc<CustomNavigationTab>(2, _omitFieldNames ? '' : 'tabs', $pb.PbFieldType.PM, subBuilder: CustomNavigationTab.create)
    ..e<NavigationTabStyle>(3, _omitFieldNames ? '' : 'tabStyle', $pb.PbFieldType.OE, defaultOrMaker: NavigationTabStyle.NAVIGATION_TAB_ICON_ONLY, valueOf: NavigationTabStyle.valueOf, enumValues: NavigationTabStyle.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CustomNavigationTabSet clone() => CustomNavigationTabSet()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CustomNavigationTabSet copyWith(void Function(CustomNavigationTabSet) updates) => super.copyWith((message) => updates(message as CustomNavigationTabSet)) as CustomNavigationTabSet;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomNavigationTabSet create() => CustomNavigationTabSet._();
  CustomNavigationTabSet createEmptyInstance() => create();
  static $pb.PbList<CustomNavigationTabSet> createRepeated() => $pb.PbList<CustomNavigationTabSet>();
  @$core.pragma('dart2js:noInline')
  static CustomNavigationTabSet getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomNavigationTabSet>(create);
  static CustomNavigationTabSet? _defaultInstance;

  /// Overrides the default `/` page. If unset, the default combined Events+Posts feed is used.
  @$pb.TagNumber(1)
  CustomHomePage get home => $_getN(0);
  @$pb.TagNumber(1)
  set home(CustomHomePage v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasHome() => $_has(0);
  @$pb.TagNumber(1)
  void clearHome() => clearField(1);
  @$pb.TagNumber(1)
  CustomHomePage ensureHome() => $_ensure(0);

  /// Overrides the default tab set (`EVENTS_TAB`, `POSTS_TAB`, `PEOPLE_TAB`, `ABOUT_TAB`) entirely.
  /// Note: existing `/events`, `/posts`, `/people`, and `/about` paths are reserved for their
  /// matching predefined tab - see [`CustomNavigationTab`](#rellm-CustomNavigationTab).path's own doc.
  /// `/` itself is overridden via `home` above instead.
  @$pb.TagNumber(2)
  $core.List<CustomNavigationTab> get tabs => $_getList(1);

  /// How every tab (Home excluded - it always shows the server's own logo/name) is laid out in the
  /// Elm nav. Purely cosmetic: it changes nothing about which tabs exist, their order, or where they
  /// link - see `NavigationTabStyle` below. Defaults to `NAVIGATION_TAB_ICON_ONLY` (proto enum value
  /// 0) both when `CustomNavigationTabSet` itself is unset and for any config saved before this
  /// field existed.
  @$pb.TagNumber(3)
  NavigationTabStyle get tabStyle => $_getN(2);
  @$pb.TagNumber(3)
  set tabStyle(NavigationTabStyle v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasTabStyle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTabStyle() => clearField(3);
}

enum CustomHomePage_Target {
  tab, 
  postId, 
  notSet
}

/// Overrides the app's default `/` page (the combined Events+Posts feed). Unlike a regular
/// `CustomNavigationTab`, this has no `path` (it's always `/`) and no `icon`/`title` (the server's
/// own name/logo are always shown for the Home tab in the nav, regardless of what it links to).
class CustomHomePage extends $pb.GeneratedMessage {
  factory CustomHomePage({
    NavigationTab? tab,
    $core.String? postId,
    $core.Iterable<$core.String>? pinnedPostIds,
    $core.bool? showEventsStrip,
    $core.bool? defaultEventsStripToRow,
    CalendarDisplayMode? defaultEventsStripCalendarDisplayMode,
  }) {
    final $result = create();
    if (tab != null) {
      $result.tab = tab;
    }
    if (postId != null) {
      $result.postId = postId;
    }
    if (pinnedPostIds != null) {
      $result.pinnedPostIds.addAll(pinnedPostIds);
    }
    if (showEventsStrip != null) {
      $result.showEventsStrip = showEventsStrip;
    }
    if (defaultEventsStripToRow != null) {
      $result.defaultEventsStripToRow = defaultEventsStripToRow;
    }
    if (defaultEventsStripCalendarDisplayMode != null) {
      $result.defaultEventsStripCalendarDisplayMode = defaultEventsStripCalendarDisplayMode;
    }
    return $result;
  }
  CustomHomePage._() : super();
  factory CustomHomePage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CustomHomePage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, CustomHomePage_Target> _CustomHomePage_TargetByTag = {
    1 : CustomHomePage_Target.tab,
    2 : CustomHomePage_Target.postId,
    0 : CustomHomePage_Target.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CustomHomePage', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..e<NavigationTab>(1, _omitFieldNames ? '' : 'tab', $pb.PbFieldType.OE, defaultOrMaker: NavigationTab.HOME_TAB, valueOf: NavigationTab.valueOf, enumValues: NavigationTab.values)
    ..aOS(2, _omitFieldNames ? '' : 'postId')
    ..pPS(3, _omitFieldNames ? '' : 'pinnedPostIds')
    ..aOB(4, _omitFieldNames ? '' : 'showEventsStrip')
    ..aOB(5, _omitFieldNames ? '' : 'defaultEventsStripToRow')
    ..e<CalendarDisplayMode>(6, _omitFieldNames ? '' : 'defaultEventsStripCalendarDisplayMode', $pb.PbFieldType.OE, defaultOrMaker: CalendarDisplayMode.CALENDAR_DISPLAY_WEEK, valueOf: CalendarDisplayMode.valueOf, enumValues: CalendarDisplayMode.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CustomHomePage clone() => CustomHomePage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CustomHomePage copyWith(void Function(CustomHomePage) updates) => super.copyWith((message) => updates(message as CustomHomePage)) as CustomHomePage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomHomePage create() => CustomHomePage._();
  CustomHomePage createEmptyInstance() => create();
  static $pb.PbList<CustomHomePage> createRepeated() => $pb.PbList<CustomHomePage>();
  @$core.pragma('dart2js:noInline')
  static CustomHomePage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomHomePage>(create);
  static CustomHomePage? _defaultInstance;

  CustomHomePage_Target whichTarget() => _CustomHomePage_TargetByTag[$_whichOneof(0)]!;
  void clearTarget() => clearField($_whichOneof(0));

  /// What `/` renders. Only `HOME_TAB` (the default, combined Events+Posts feed), `EVENTS_TAB`,
  /// or `POSTS_TAB` are valid here - never `PEOPLE_TAB`/`ABOUT_TAB`.
  @$pb.TagNumber(1)
  NavigationTab get tab => $_getN(0);
  @$pb.TagNumber(1)
  set tab(NavigationTab v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasTab() => $_has(0);
  @$pb.TagNumber(1)
  void clearTab() => clearField(1);

  /// Renders a specific Post at `/` instead (e.g. for a custom business site's landing page).
  @$pb.TagNumber(2)
  $core.String get postId => $_getSZ(1);
  @$pb.TagNumber(2)
  set postId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPostId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPostId() => clearField(2);

  /// Posts pinned to the top of the home page, above its normal content. Loaded the same way
  /// `StarredPanel` loads its own starred posts (i.e., conditionally fetching each pinned post's
  /// backing Event alongside it, for posts that are actually about an Event).
  @$pb.TagNumber(3)
  $core.List<$core.String> get pinnedPostIds => $_getList(2);

  /// Shows the Events strip (the same horizontal upcoming-events row the default `HOME_TAB` always
  /// shows above its Posts feed) above `target`'s own content. Only meaningful when `target` is
  /// `post_id` (pins an Events strip above that single Post); has no effect when `target` is
  /// unset/`HOME_TAB` (the strip is already shown) or `POSTS_TAB` (equivalent to just leaving
  /// `target` unset).
  @$pb.TagNumber(4)
  $core.bool get showEventsStrip => $_getBF(3);
  @$pb.TagNumber(4)
  set showEventsStrip($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasShowEventsStrip() => $_has(3);
  @$pb.TagNumber(4)
  void clearShowEventsStrip() => clearField(4);

  /// Whenever an Events strip is shown above other content - `show_events_strip` is set, or
  /// `target` is unset/`HOME_TAB` (whose strip is always shown) - whether it defaults to its
  /// row/list layout instead of a calendar. Unset defaults to the calendar layout.
  @$pb.TagNumber(5)
  $core.bool get defaultEventsStripToRow => $_getBF(4);
  @$pb.TagNumber(5)
  set defaultEventsStripToRow($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDefaultEventsStripToRow() => $_has(4);
  @$pb.TagNumber(5)
  void clearDefaultEventsStripToRow() => clearField(5);

  /// Whenever an Events strip is shown above other content (see `default_events_strip_to_row`'s own
  /// doc) and defaults to the calendar layout (`default_events_strip_to_row` is unset), which
  /// granularity it opens to. Defaults to `CALENDAR_DISPLAY_WEEK`.
  @$pb.TagNumber(6)
  CalendarDisplayMode get defaultEventsStripCalendarDisplayMode => $_getN(5);
  @$pb.TagNumber(6)
  set defaultEventsStripCalendarDisplayMode(CalendarDisplayMode v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasDefaultEventsStripCalendarDisplayMode() => $_has(5);
  @$pb.TagNumber(6)
  void clearDefaultEventsStripCalendarDisplayMode() => clearField(6);
}

enum CustomNavigationTab_Target {
  tab, 
  postId, 
  isProfile, 
  notSet
}

enum CustomNavigationTab_Icon {
  emojiIcon, 
  iconMediaId, 
  notSet
}

/// Either one of the app's predefined tabs, a Post, or a user profile - reachable at `path`.
class CustomNavigationTab extends $pb.GeneratedMessage {
  factory CustomNavigationTab({
    NavigationTab? tab,
    $core.String? postId,
    $core.bool? isProfile,
    $core.String? emojiIcon,
    $core.String? iconMediaId,
    $core.String? title,
    $core.String? path,
  }) {
    final $result = create();
    if (tab != null) {
      $result.tab = tab;
    }
    if (postId != null) {
      $result.postId = postId;
    }
    if (isProfile != null) {
      $result.isProfile = isProfile;
    }
    if (emojiIcon != null) {
      $result.emojiIcon = emojiIcon;
    }
    if (iconMediaId != null) {
      $result.iconMediaId = iconMediaId;
    }
    if (title != null) {
      $result.title = title;
    }
    if (path != null) {
      $result.path = path;
    }
    return $result;
  }
  CustomNavigationTab._() : super();
  factory CustomNavigationTab.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CustomNavigationTab.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, CustomNavigationTab_Target> _CustomNavigationTab_TargetByTag = {
    1 : CustomNavigationTab_Target.tab,
    2 : CustomNavigationTab_Target.postId,
    3 : CustomNavigationTab_Target.isProfile,
    0 : CustomNavigationTab_Target.notSet
  };
  static const $core.Map<$core.int, CustomNavigationTab_Icon> _CustomNavigationTab_IconByTag = {
    10 : CustomNavigationTab_Icon.emojiIcon,
    11 : CustomNavigationTab_Icon.iconMediaId,
    0 : CustomNavigationTab_Icon.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CustomNavigationTab', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..oo(1, [10, 11])
    ..e<NavigationTab>(1, _omitFieldNames ? '' : 'tab', $pb.PbFieldType.OE, defaultOrMaker: NavigationTab.HOME_TAB, valueOf: NavigationTab.valueOf, enumValues: NavigationTab.values)
    ..aOS(2, _omitFieldNames ? '' : 'postId')
    ..aOB(3, _omitFieldNames ? '' : 'isProfile')
    ..aOS(10, _omitFieldNames ? '' : 'emojiIcon')
    ..aOS(11, _omitFieldNames ? '' : 'iconMediaId')
    ..aOS(12, _omitFieldNames ? '' : 'title')
    ..aOS(13, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CustomNavigationTab clone() => CustomNavigationTab()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CustomNavigationTab copyWith(void Function(CustomNavigationTab) updates) => super.copyWith((message) => updates(message as CustomNavigationTab)) as CustomNavigationTab;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CustomNavigationTab create() => CustomNavigationTab._();
  CustomNavigationTab createEmptyInstance() => create();
  static $pb.PbList<CustomNavigationTab> createRepeated() => $pb.PbList<CustomNavigationTab>();
  @$core.pragma('dart2js:noInline')
  static CustomNavigationTab getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomNavigationTab>(create);
  static CustomNavigationTab? _defaultInstance;

  CustomNavigationTab_Target whichTarget() => _CustomNavigationTab_TargetByTag[$_whichOneof(0)]!;
  void clearTarget() => clearField($_whichOneof(0));

  CustomNavigationTab_Icon whichIcon() => _CustomNavigationTab_IconByTag[$_whichOneof(1)]!;
  void clearIcon() => clearField($_whichOneof(1));

  /// Links to one of the app's predefined tabs/pages.
  @$pb.TagNumber(1)
  NavigationTab get tab => $_getN(0);
  @$pb.TagNumber(1)
  set tab(NavigationTab v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasTab() => $_has(0);
  @$pb.TagNumber(1)
  void clearTab() => clearField(1);

  /// Links to a specific Post (e.g. for a custom business site's page).
  @$pb.TagNumber(2)
  $core.String get postId => $_getSZ(1);
  @$pb.TagNumber(2)
  set postId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPostId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPostId() => clearField(2);

  /// Indicates the custom tab is for an actual user profile - `path` is that user's username.
  /// Ultimately this isn't very "custom" in terms of the URL scheme, just it being a navigation tab.
  @$pb.TagNumber(3)
  $core.bool get isProfile => $_getBF(2);
  @$pb.TagNumber(3)
  set isProfile($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIsProfile() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsProfile() => clearField(3);

  /// Emoji shown as the tab's icon (e.g. "🎪").
  @$pb.TagNumber(10)
  $core.String get emojiIcon => $_getSZ(3);
  @$pb.TagNumber(10)
  set emojiIcon($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(10)
  $core.bool hasEmojiIcon() => $_has(3);
  @$pb.TagNumber(10)
  void clearEmojiIcon() => clearField(10);

  /// Media ID (see [`Media`](#rellm-Media) APIs) of an image shown as the tab's icon.
  @$pb.TagNumber(11)
  $core.String get iconMediaId => $_getSZ(4);
  @$pb.TagNumber(11)
  set iconMediaId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(11)
  $core.bool hasIconMediaId() => $_has(4);
  @$pb.TagNumber(11)
  void clearIconMediaId() => clearField(11);

  /// Title shown for the tab. Defaults to the predefined tab's/Post's title if unset.
  @$pb.TagNumber(12)
  $core.String get title => $_getSZ(5);
  @$pb.TagNumber(12)
  set title($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(12)
  $core.bool hasTitle() => $_has(5);
  @$pb.TagNumber(12)
  void clearTitle() => clearField(12);

  /// The path this tab is reachable at, e.g. `gigs` for a band's `/gigs` link to the Events page,
  /// or `weddings` for a Post about wedding offerings. Must be distinct across every entry in
  /// `CustomNavigationTabSet.tabs`. Note: `events`, `posts`, `people`, and `about` are reserved --
  /// each may only be used to (redundantly) point back at its own matching predefined tab, never
  /// remapped to a different tab or a Post. `/` itself is never reachable this way - it's
  /// overridden via `CustomNavigationTabSet.home` instead.
  @$pb.TagNumber(13)
  $core.String get path => $_getSZ(6);
  @$pb.TagNumber(13)
  set path($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(13)
  $core.bool hasPath() => $_has(6);
  @$pb.TagNumber(13)
  void clearPath() => clearField(13);
}

/// Color in ARGB hex format (i.e `0xAARRGGBB`).
class ServerColors extends $pb.GeneratedMessage {
  factory ServerColors({
    $core.int? primary,
    $core.int? navigation,
    $core.int? author,
    $core.int? admin,
    $core.int? moderator,
  }) {
    final $result = create();
    if (primary != null) {
      $result.primary = primary;
    }
    if (navigation != null) {
      $result.navigation = navigation;
    }
    if (author != null) {
      $result.author = author;
    }
    if (admin != null) {
      $result.admin = admin;
    }
    if (moderator != null) {
      $result.moderator = moderator;
    }
    return $result;
  }
  ServerColors._() : super();
  factory ServerColors.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ServerColors.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ServerColors', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'primary', $pb.PbFieldType.OU3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'navigation', $pb.PbFieldType.OU3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'author', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'admin', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'moderator', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ServerColors clone() => ServerColors()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ServerColors copyWith(void Function(ServerColors) updates) => super.copyWith((message) => updates(message as ServerColors)) as ServerColors;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerColors create() => ServerColors._();
  ServerColors createEmptyInstance() => create();
  static $pb.PbList<ServerColors> createRepeated() => $pb.PbList<ServerColors>();
  @$core.pragma('dart2js:noInline')
  static ServerColors getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ServerColors>(create);
  static ServerColors? _defaultInstance;

  /// App Bar/primary accent color.
  @$pb.TagNumber(1)
  $core.int get primary => $_getIZ(0);
  @$pb.TagNumber(1)
  set primary($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrimary() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrimary() => clearField(1);

  /// Nav/secondary accent color.
  @$pb.TagNumber(2)
  $core.int get navigation => $_getIZ(1);
  @$pb.TagNumber(2)
  set navigation($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNavigation() => $_has(1);
  @$pb.TagNumber(2)
  void clearNavigation() => clearField(2);

  /// Color used on author of a post in discussion threads for it.
  @$pb.TagNumber(3)
  $core.int get author => $_getIZ(2);
  @$pb.TagNumber(3)
  set author($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAuthor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthor() => clearField(3);

  /// Color used on author for admin posts.
  @$pb.TagNumber(4)
  $core.int get admin => $_getIZ(3);
  @$pb.TagNumber(4)
  set admin($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAdmin() => $_has(3);
  @$pb.TagNumber(4)
  void clearAdmin() => clearField(4);

  /// Color used on author for moderator posts.
  @$pb.TagNumber(5)
  $core.int get moderator => $_getIZ(4);
  @$pb.TagNumber(5)
  set moderator($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModerator() => $_has(4);
  @$pb.TagNumber(5)
  void clearModerator() => clearField(5);
}

/// Web Push (VAPID) configuration for the server.
class WebPushConfig extends $pb.GeneratedMessage {
  factory WebPushConfig({
    $core.String? publicVapidKey,
    $core.String? privateVapidKey,
  }) {
    final $result = create();
    if (publicVapidKey != null) {
      $result.publicVapidKey = publicVapidKey;
    }
    if (privateVapidKey != null) {
      $result.privateVapidKey = privateVapidKey;
    }
    return $result;
  }
  WebPushConfig._() : super();
  factory WebPushConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WebPushConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WebPushConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'publicVapidKey')
    ..aOS(2, _omitFieldNames ? '' : 'privateVapidKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WebPushConfig clone() => WebPushConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WebPushConfig copyWith(void Function(WebPushConfig) updates) => super.copyWith((message) => updates(message as WebPushConfig)) as WebPushConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WebPushConfig create() => WebPushConfig._();
  WebPushConfig createEmptyInstance() => create();
  static $pb.PbList<WebPushConfig> createRepeated() => $pb.PbList<WebPushConfig>();
  @$core.pragma('dart2js:noInline')
  static WebPushConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WebPushConfig>(create);
  static WebPushConfig? _defaultInstance;

  /// Public VAPID key for the server.
  @$pb.TagNumber(1)
  $core.String get publicVapidKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set publicVapidKey($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPublicVapidKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicVapidKey() => clearField(1);

  /// Private VAPID key for the server. *Never serialized to the client.*
  /// Admins: Edit this in the database's JSONB column directly.
  @$pb.TagNumber(2)
  $core.String get privateVapidKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set privateVapidKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPrivateVapidKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrivateVapidKey() => clearField(2);
}

/// Twilio credentials, authenticated via a Twilio **API Key** (`twilio_api_key_sid`/
/// `twilio_api_key_secret`) -- deliberately *not* the account's own Auth Token. A server's Auth
/// Token is a single unscoped, unrevocable-without-rotating-everything credential with full access
/// to the whole Twilio account; an API Key is its own separate, individually-revocable credential
/// pair meant for exactly this kind of integration. `twilio_account_sid` is still required (Twilio
/// resource URLs are always addressed by the actual Account SID), but it is *not* used to
/// authenticate -- only the API Key SID/Secret pair is. See
/// https://www.twilio.com/docs/iam/api-keys/restricted-api-keys for the recommended
/// permission when creating one: `/twilio/messaging/messages/create` (nothing else is needed just
/// to send verification SMS). See `docs/contact_integrations.md` for full setup steps (API key
/// creation, inbound webhook registration), and [`ContactMethod`](#rellm-ContactMethod)
/// (`users.proto`) for how a verified `tel:` contact method surfaces this provider.
class TwilioConfig extends $pb.GeneratedMessage {
  factory TwilioConfig({
    $core.bool? twilioEnabled,
    $core.String? twilioApiKeySecret,
    $core.String? twilioAccountSid,
    $core.String? twilioFromNumber,
    $core.String? twilioApiKeySid,
    $core.String? twilioWebhookSigningKey,
  }) {
    final $result = create();
    if (twilioEnabled != null) {
      $result.twilioEnabled = twilioEnabled;
    }
    if (twilioApiKeySecret != null) {
      $result.twilioApiKeySecret = twilioApiKeySecret;
    }
    if (twilioAccountSid != null) {
      $result.twilioAccountSid = twilioAccountSid;
    }
    if (twilioFromNumber != null) {
      $result.twilioFromNumber = twilioFromNumber;
    }
    if (twilioApiKeySid != null) {
      $result.twilioApiKeySid = twilioApiKeySid;
    }
    if (twilioWebhookSigningKey != null) {
      $result.twilioWebhookSigningKey = twilioWebhookSigningKey;
    }
    return $result;
  }
  TwilioConfig._() : super();
  factory TwilioConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TwilioConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TwilioConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'twilioEnabled')
    ..aOS(2, _omitFieldNames ? '' : 'twilioApiKeySecret')
    ..aOS(3, _omitFieldNames ? '' : 'twilioAccountSid')
    ..aOS(4, _omitFieldNames ? '' : 'twilioFromNumber')
    ..aOS(5, _omitFieldNames ? '' : 'twilioApiKeySid')
    ..aOS(6, _omitFieldNames ? '' : 'twilioWebhookSigningKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TwilioConfig clone() => TwilioConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TwilioConfig copyWith(void Function(TwilioConfig) updates) => super.copyWith((message) => updates(message as TwilioConfig)) as TwilioConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TwilioConfig create() => TwilioConfig._();
  TwilioConfig createEmptyInstance() => create();
  static $pb.PbList<TwilioConfig> createRepeated() => $pb.PbList<TwilioConfig>();
  @$core.pragma('dart2js:noInline')
  static TwilioConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TwilioConfig>(create);
  static TwilioConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get twilioEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set twilioEnabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTwilioEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearTwilioEnabled() => clearField(1);

  /// The Twilio API Key's Secret, used as the Basic Auth password. Never serialized once written.
  @$pb.TagNumber(2)
  $core.String get twilioApiKeySecret => $_getSZ(1);
  @$pb.TagNumber(2)
  set twilioApiKeySecret($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTwilioApiKeySecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearTwilioApiKeySecret() => clearField(2);

  /// The Twilio Account SID (starts with `AC`). Used only in the API's URL path -- *never* as an
  /// authentication credential. Public (among admins) -- freely serialized.
  @$pb.TagNumber(3)
  $core.String get twilioAccountSid => $_getSZ(2);
  @$pb.TagNumber(3)
  set twilioAccountSid($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTwilioAccountSid() => $_has(2);
  @$pb.TagNumber(3)
  void clearTwilioAccountSid() => clearField(3);

  /// The Twilio-provisioned sending number for outbound verification SMS. Not secret.
  @$pb.TagNumber(4)
  $core.String get twilioFromNumber => $_getSZ(3);
  @$pb.TagNumber(4)
  set twilioFromNumber($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTwilioFromNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearTwilioFromNumber() => clearField(4);

  /// The Twilio API Key's SID (starts with `SK`), used as the Basic Auth username. Public (among
  /// admins) -- freely serialized; it's useless without the Secret below, same as a username alone.
  @$pb.TagNumber(5)
  $core.String get twilioApiKeySid => $_getSZ(4);
  @$pb.TagNumber(5)
  set twilioApiKeySid($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTwilioApiKeySid() => $_has(4);
  @$pb.TagNumber(5)
  void clearTwilioApiKeySid() => clearField(5);

  /// Optional -- the Twilio Account's Auth Token, used *only* to verify the `X-Twilio-Signature`
  /// header on inbound deliveries to `/contact_integrations/twilio/receive` (see
  /// https://www.twilio.com/docs/usage/webhooks/webhooks-security and
  /// `docs/contact_integrations.md`). Never used to authenticate outbound API calls -- this
  /// message's own doc explains why the Auth Token is deliberately excluded from that role; this
  /// is the one narrow exception, since signature verification is the one thing only the Auth
  /// Token (not an API Key) can do. Unset means inbound deliveries are accepted without signature
  /// verification. Write-only, like every other credential here, but distinctly from those:
  /// `optional` so a client can tell *whether* a key is configured (`Some`/`None`) without ever
  /// seeing its real value -- once set, `to_proto` blanks this to `Some("")` (not `None`), so
  /// "configured but hidden" and "never configured" stay distinguishable. Sending an empty value
  /// back on `ConfigureServer` means "leave whatever's already stored alone," same as every other
  /// write-only field's blank-means-no-op rule.
  @$pb.TagNumber(6)
  $core.String get twilioWebhookSigningKey => $_getSZ(5);
  @$pb.TagNumber(6)
  set twilioWebhookSigningKey($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTwilioWebhookSigningKey() => $_has(5);
  @$pb.TagNumber(6)
  void clearTwilioWebhookSigningKey() => clearField(6);
}

/// Telnyx (https://telnyx.com) Config -- an alternative SMS verification provider to
/// [`TwilioConfig`](#rellm-TwilioConfig), with a simpler single-API-key auth model like
/// [`BirdConfig`](#rellm-BirdConfig)'s. See `docs/contact_integrations.md` for full setup steps.
class TelnyxConfig extends $pb.GeneratedMessage {
  factory TelnyxConfig({
    $core.bool? telnyxEnabled,
    $core.String? telnyxApiKey,
    $core.String? telnyxFromNumber,
    $core.String? telnyxMessagingProfileId,
    $core.String? telnyxWebhookSigningKey,
  }) {
    final $result = create();
    if (telnyxEnabled != null) {
      $result.telnyxEnabled = telnyxEnabled;
    }
    if (telnyxApiKey != null) {
      $result.telnyxApiKey = telnyxApiKey;
    }
    if (telnyxFromNumber != null) {
      $result.telnyxFromNumber = telnyxFromNumber;
    }
    if (telnyxMessagingProfileId != null) {
      $result.telnyxMessagingProfileId = telnyxMessagingProfileId;
    }
    if (telnyxWebhookSigningKey != null) {
      $result.telnyxWebhookSigningKey = telnyxWebhookSigningKey;
    }
    return $result;
  }
  TelnyxConfig._() : super();
  factory TelnyxConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TelnyxConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TelnyxConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'telnyxEnabled')
    ..aOS(2, _omitFieldNames ? '' : 'telnyxApiKey')
    ..aOS(3, _omitFieldNames ? '' : 'telnyxFromNumber')
    ..aOS(4, _omitFieldNames ? '' : 'telnyxMessagingProfileId')
    ..aOS(5, _omitFieldNames ? '' : 'telnyxWebhookSigningKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TelnyxConfig clone() => TelnyxConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TelnyxConfig copyWith(void Function(TelnyxConfig) updates) => super.copyWith((message) => updates(message as TelnyxConfig)) as TelnyxConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TelnyxConfig create() => TelnyxConfig._();
  TelnyxConfig createEmptyInstance() => create();
  static $pb.PbList<TelnyxConfig> createRepeated() => $pb.PbList<TelnyxConfig>();
  @$core.pragma('dart2js:noInline')
  static TelnyxConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TelnyxConfig>(create);
  static TelnyxConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get telnyxEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set telnyxEnabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTelnyxEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearTelnyxEnabled() => clearField(1);

  /// The Telnyx v2 API Key (starts with `KEY`), used as Bearer auth for Telnyx's Messaging API
  /// (`POST /v2/messages`). Never serialized once written -- same write-only treatment as
  /// [`TwilioConfig.twilio_api_key_secret`](#rellm-TwilioConfig)/
  /// [`BirdConfig.bird_access_key`](#rellm-BirdConfig).
  @$pb.TagNumber(2)
  $core.String get telnyxApiKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set telnyxApiKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTelnyxApiKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearTelnyxApiKey() => clearField(2);

  /// The Telnyx-provisioned sending number for outbound verification SMS (E.164, e.g. a toll-free
  /// number). Not secret.
  @$pb.TagNumber(3)
  $core.String get telnyxFromNumber => $_getSZ(2);
  @$pb.TagNumber(3)
  set telnyxFromNumber($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTelnyxFromNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearTelnyxFromNumber() => clearField(3);

  /// The Telnyx Messaging Profile ID that `telnyx_from_number` is assigned to -- required by
  /// Telnyx's Messaging API to actually send (`messaging_profile_id` on `POST /v2/messages`). Not
  /// secret.
  @$pb.TagNumber(4)
  $core.String get telnyxMessagingProfileId => $_getSZ(3);
  @$pb.TagNumber(4)
  set telnyxMessagingProfileId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTelnyxMessagingProfileId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTelnyxMessagingProfileId() => clearField(4);

  /// Optional -- Telnyx's account-level public key (Mission Control Portal -> Keys & Credentials ->
  /// Public Key), used to verify the `telnyx-signature-ed25519`/`telnyx-timestamp` headers on
  /// inbound deliveries to `/contact_integrations/telnyx/receive` (Ed25519; see
  /// https://developers.telnyx.com/docs/messaging/messages/receiving-webhooks and
  /// `docs/contact_integrations.md`). Actually a public key, not a secret, but kept write-only
  /// (never serialized once written) for the same "don't echo config back" treatment as every
  /// other credential here. Unset means inbound deliveries are accepted without signature
  /// verification. `optional` (not plain `string`) for the same "`Some`/`None` distinguishable from
  /// a client without ever seeing the real value" reason as
  /// [`TwilioConfig.twilio_webhook_signing_key`](#rellm-TwilioConfig).
  @$pb.TagNumber(5)
  $core.String get telnyxWebhookSigningKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set telnyxWebhookSigningKey($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTelnyxWebhookSigningKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearTelnyxWebhookSigningKey() => clearField(5);
}

/// Bird (https://bird.com, formerly MessageBird) Config -- an alternative SMS verification
/// provider to [`TwilioConfig`](#rellm-TwilioConfig), with a simpler single-API-key auth model. See
/// `docs/contact_integrations.md` for full setup steps.
class BirdConfig extends $pb.GeneratedMessage {
  factory BirdConfig({
    $core.bool? birdEnabled,
    $core.String? birdAccessKey,
    $core.String? birdFrom,
    $core.String? birdRegion,
    $core.String? birdWebhookSigningKey,
  }) {
    final $result = create();
    if (birdEnabled != null) {
      $result.birdEnabled = birdEnabled;
    }
    if (birdAccessKey != null) {
      $result.birdAccessKey = birdAccessKey;
    }
    if (birdFrom != null) {
      $result.birdFrom = birdFrom;
    }
    if (birdRegion != null) {
      $result.birdRegion = birdRegion;
    }
    if (birdWebhookSigningKey != null) {
      $result.birdWebhookSigningKey = birdWebhookSigningKey;
    }
    return $result;
  }
  BirdConfig._() : super();
  factory BirdConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BirdConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BirdConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'birdEnabled')
    ..aOS(2, _omitFieldNames ? '' : 'birdAccessKey')
    ..aOS(3, _omitFieldNames ? '' : 'birdFrom')
    ..aOS(4, _omitFieldNames ? '' : 'birdRegion')
    ..aOS(5, _omitFieldNames ? '' : 'birdWebhookSigningKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BirdConfig clone() => BirdConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BirdConfig copyWith(void Function(BirdConfig) updates) => super.copyWith((message) => updates(message as BirdConfig)) as BirdConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BirdConfig create() => BirdConfig._();
  BirdConfig createEmptyInstance() => create();
  static $pb.PbList<BirdConfig> createRepeated() => $pb.PbList<BirdConfig>();
  @$core.pragma('dart2js:noInline')
  static BirdConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BirdConfig>(create);
  static BirdConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get birdEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set birdEnabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasBirdEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearBirdEnabled() => clearField(1);

  /// The Bird workspace's API access key. Never serialized once written.
  @$pb.TagNumber(2)
  $core.String get birdAccessKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set birdAccessKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasBirdAccessKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearBirdAccessKey() => clearField(2);

  /// The originator for outbound verification SMS -- an owned number, alphanumeric sender ID
  /// (3-11 chars), or short code, as configured in the Bird workspace. Not secret.
  @$pb.TagNumber(3)
  $core.String get birdFrom => $_getSZ(2);
  @$pb.TagNumber(3)
  set birdFrom($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBirdFrom() => $_has(2);
  @$pb.TagNumber(3)
  void clearBirdFrom() => clearField(3);

  /// Which Bird API region to call ("us1" or "eu1", per Bird's own regional API hosts). Not
  /// secret. Empty defaults to "us1".
  @$pb.TagNumber(4)
  $core.String get birdRegion => $_getSZ(3);
  @$pb.TagNumber(4)
  set birdRegion($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasBirdRegion() => $_has(3);
  @$pb.TagNumber(4)
  void clearBirdRegion() => clearField(4);

  /// Optional -- the Standard Webhooks signing secret (starts with `whsec_`) for the SMS channel
  /// subscription delivering to `/contact_integrations/bird/receive`, used to verify the
  /// `webhook-id`/`webhook-timestamp`/`webhook-signature` headers on inbound deliveries (HMAC-SHA256;
  /// see https://www.standardwebhooks.com and `docs/contact_integrations.md`). Blank/unset means
  /// inbound deliveries are accepted without signature verification. `optional` (not plain
  /// `string`) for the same "`Some`/`None` distinguishable from a client without ever seeing the
  /// real value" reason as
  /// [`TwilioConfig.twilio_webhook_signing_key`](#rellm-TwilioConfig).
  @$pb.TagNumber(5)
  $core.String get birdWebhookSigningKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set birdWebhookSigningKey($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasBirdWebhookSigningKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearBirdWebhookSigningKey() => clearField(5);
}

/// Stripe credentials backing the Marketplace (`market.proto`). Used both to create Checkout
/// Sessions/off-session renewal PaymentIntents (`stripe_secret_key`) and to verify incoming
/// webhook deliveries (`stripe_webhook_signing_secret`).
class StripeConfig extends $pb.GeneratedMessage {
  factory StripeConfig({
    $core.bool? stripeEnabled,
    $core.String? stripeSecretKey,
    $core.String? stripePublishableKey,
    $core.String? stripeWebhookSigningSecret,
  }) {
    final $result = create();
    if (stripeEnabled != null) {
      $result.stripeEnabled = stripeEnabled;
    }
    if (stripeSecretKey != null) {
      $result.stripeSecretKey = stripeSecretKey;
    }
    if (stripePublishableKey != null) {
      $result.stripePublishableKey = stripePublishableKey;
    }
    if (stripeWebhookSigningSecret != null) {
      $result.stripeWebhookSigningSecret = stripeWebhookSigningSecret;
    }
    return $result;
  }
  StripeConfig._() : super();
  factory StripeConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StripeConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StripeConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'stripeEnabled')
    ..aOS(2, _omitFieldNames ? '' : 'stripeSecretKey')
    ..aOS(3, _omitFieldNames ? '' : 'stripePublishableKey')
    ..aOS(4, _omitFieldNames ? '' : 'stripeWebhookSigningSecret')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StripeConfig clone() => StripeConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StripeConfig copyWith(void Function(StripeConfig) updates) => super.copyWith((message) => updates(message as StripeConfig)) as StripeConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StripeConfig create() => StripeConfig._();
  StripeConfig createEmptyInstance() => create();
  static $pb.PbList<StripeConfig> createRepeated() => $pb.PbList<StripeConfig>();
  @$core.pragma('dart2js:noInline')
  static StripeConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StripeConfig>(create);
  static StripeConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get stripeEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set stripeEnabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStripeEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearStripeEnabled() => clearField(1);

  /// Stripe Secret Key (starts with `sk_`), used as Bearer auth for all Stripe API calls made by
  /// this server (Checkout Session creation, off-session renewal charges). Never serialized once
  /// written -- same write-only treatment as `TwilioConfig.twilio_api_key_secret`.
  @$pb.TagNumber(2)
  $core.String get stripeSecretKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set stripeSecretKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStripeSecretKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearStripeSecretKey() => clearField(2);

  /// Stripe Publishable Key (starts with `pk_`). Not secret -- kept here (rather than derived from
  /// `stripe_secret_key`) so a future client-side Stripe Elements integration has what it needs,
  /// even though the current Checkout-based flow doesn't use it server-side at all.
  @$pb.TagNumber(3)
  $core.String get stripePublishableKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set stripePublishableKey($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStripePublishableKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearStripePublishableKey() => clearField(3);

  /// Signing secret (starts with `whsec_`) for the `/webhooks/stripe` endpoint, used to verify the
  /// `Stripe-Signature` header on incoming webhook deliveries. Never serialized once written --
  /// same write-only treatment as `stripe_secret_key` above.
  @$pb.TagNumber(4)
  $core.String get stripeWebhookSigningSecret => $_getSZ(3);
  @$pb.TagNumber(4)
  set stripeWebhookSigningSecret($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStripeWebhookSigningSecret() => $_has(3);
  @$pb.TagNumber(4)
  void clearStripeWebhookSigningSecret() => clearField(4);
}

/// Stalwart is an extablished, open-source Rust email/contact/calendar server (think an Outlook or Google Workspace competitor).
/// Currently Rellm supports receiving emails via Stalwart webhook configurations.
class StalwartConfig extends $pb.GeneratedMessage {
  factory StalwartConfig({
    $core.bool? stalwartReceivingEnabled,
  }) {
    final $result = create();
    if (stalwartReceivingEnabled != null) {
      $result.stalwartReceivingEnabled = stalwartReceivingEnabled;
    }
    return $result;
  }
  StalwartConfig._() : super();
  factory StalwartConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StalwartConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StalwartConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'stalwartReceivingEnabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StalwartConfig clone() => StalwartConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StalwartConfig copyWith(void Function(StalwartConfig) updates) => super.copyWith((message) => updates(message as StalwartConfig)) as StalwartConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StalwartConfig create() => StalwartConfig._();
  StalwartConfig createEmptyInstance() => create();
  static $pb.PbList<StalwartConfig> createRepeated() => $pb.PbList<StalwartConfig>();
  @$core.pragma('dart2js:noInline')
  static StalwartConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StalwartConfig>(create);
  static StalwartConfig? _defaultInstance;

  /// Enables receiving emails from the private, unsecured cluster-facing HTTP server at :27705/email.
  @$pb.TagNumber(1)
  $core.bool get stalwartReceivingEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set stalwartReceivingEnabled($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStalwartReceivingEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearStalwartReceivingEnabled() => clearField(1);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
