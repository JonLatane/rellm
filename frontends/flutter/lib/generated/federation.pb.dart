//
//  Generated code. Do not modify.
//  source: federation.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Version information for the Rellm server.
class GetServiceVersionResponse extends $pb.GeneratedMessage {
  factory GetServiceVersionResponse({
    $core.String? version,
  }) {
    final $result = create();
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }
  GetServiceVersionResponse._() : super();
  factory GetServiceVersionResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetServiceVersionResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetServiceVersionResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'version')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetServiceVersionResponse clone() => GetServiceVersionResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetServiceVersionResponse copyWith(void Function(GetServiceVersionResponse) updates) => super.copyWith((message) => updates(message as GetServiceVersionResponse)) as GetServiceVersionResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetServiceVersionResponse create() => GetServiceVersionResponse._();
  GetServiceVersionResponse createEmptyInstance() => create();
  static $pb.PbList<GetServiceVersionResponse> createRepeated() => $pb.PbList<GetServiceVersionResponse>();
  @$core.pragma('dart2js:noInline')
  static GetServiceVersionResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetServiceVersionResponse>(create);
  static GetServiceVersionResponse? _defaultInstance;

  /// The version of the Rellm server. May be suffixed with the GitHub SHA of the commit
  /// that generated the binary for the server.
  @$pb.TagNumber(1)
  $core.String get version => $_getSZ(0);
  @$pb.TagNumber(1)
  set version($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => clearField(1);
}

/// The federation configuration for a Rellm server.
class FederationInfo extends $pb.GeneratedMessage {
  factory FederationInfo({
    $core.Iterable<FederatedServer>? servers,
    FacebookAuthConfig? facebookAuthConfig,
    XTwitterAuthConfig? xTwitterAuthConfig,
    $core.Iterable<MastodonServer>? mastodonServers,
    $core.bool? unsecureLocalhostFederatedAuthEnabled,
  }) {
    final $result = create();
    if (servers != null) {
      $result.servers.addAll(servers);
    }
    if (facebookAuthConfig != null) {
      $result.facebookAuthConfig = facebookAuthConfig;
    }
    if (xTwitterAuthConfig != null) {
      $result.xTwitterAuthConfig = xTwitterAuthConfig;
    }
    if (mastodonServers != null) {
      $result.mastodonServers.addAll(mastodonServers);
    }
    if (unsecureLocalhostFederatedAuthEnabled != null) {
      $result.unsecureLocalhostFederatedAuthEnabled = unsecureLocalhostFederatedAuthEnabled;
    }
    return $result;
  }
  FederationInfo._() : super();
  factory FederationInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FederationInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FederationInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<FederatedServer>(1, _omitFieldNames ? '' : 'servers', $pb.PbFieldType.PM, subBuilder: FederatedServer.create)
    ..aOM<FacebookAuthConfig>(2, _omitFieldNames ? '' : 'facebookAuthConfig', subBuilder: FacebookAuthConfig.create)
    ..aOM<XTwitterAuthConfig>(3, _omitFieldNames ? '' : 'xTwitterAuthConfig', subBuilder: XTwitterAuthConfig.create)
    ..pc<MastodonServer>(4, _omitFieldNames ? '' : 'mastodonServers', $pb.PbFieldType.PM, subBuilder: MastodonServer.create)
    ..aOB(5, _omitFieldNames ? '' : 'unsecureLocalhostFederatedAuthEnabled')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FederationInfo clone() => FederationInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FederationInfo copyWith(void Function(FederationInfo) updates) => super.copyWith((message) => updates(message as FederationInfo)) as FederationInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FederationInfo create() => FederationInfo._();
  FederationInfo createEmptyInstance() => create();
  static $pb.PbList<FederationInfo> createRepeated() => $pb.PbList<FederationInfo>();
  @$core.pragma('dart2js:noInline')
  static FederationInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FederationInfo>(create);
  static FederationInfo? _defaultInstance;

  /// A list of servers that this server will federate with.
  @$pb.TagNumber(1)
  $core.List<FederatedServer> get servers => $_getList(0);

  /// Facebook authentication configuration for the server. If set, allows users to create Facebook (and Instagram) SyncDestinations for their Posts and Occasions.
  @$pb.TagNumber(2)
  FacebookAuthConfig get facebookAuthConfig => $_getN(1);
  @$pb.TagNumber(2)
  set facebookAuthConfig(FacebookAuthConfig v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasFacebookAuthConfig() => $_has(1);
  @$pb.TagNumber(2)
  void clearFacebookAuthConfig() => clearField(2);
  @$pb.TagNumber(2)
  FacebookAuthConfig ensureFacebookAuthConfig() => $_ensure(1);

  /// X (Twitter) authentication configuration for the server. If set, allows users to create X (Twitter) SyncDestinations
  /// for their Posts and Occasions - an admin registers one X Developer App here, and every
  /// user on the server connects their own X account through it via OAuth, the same relationship
  /// `facebook_auth_config` has to individual Facebook Pages. Until set, [`XTwitterAccount`](#rellm-XTwitterAccount)
  /// SyncDestinations always fail with `x_twitter_app_not_configured`.
  @$pb.TagNumber(3)
  XTwitterAuthConfig get xTwitterAuthConfig => $_getN(2);
  @$pb.TagNumber(3)
  set xTwitterAuthConfig(XTwitterAuthConfig v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasXTwitterAuthConfig() => $_has(2);
  @$pb.TagNumber(3)
  void clearXTwitterAuthConfig() => clearField(3);
  @$pb.TagNumber(3)
  XTwitterAuthConfig ensureXTwitterAuthConfig() => $_ensure(2);

  /// Mastodon instances this server has a registered OAuth app on, letting users connect/read their
  /// own account on that instance. Unlike Facebook/X, Mastodon has no single central platform to
  /// register an app against - every instance is its own separate OAuth authority, so an admin has
  /// to register an app on each instance individually before users on it can connect. If a user's
  /// instance isn't listed here, clients should surface a "not configured" alert rather than
  /// attempting to open an OAuth popup with no app to authorize against. (A client could instead
  /// dynamically self-register a throwaway app with the instance directly, via Mastodon's own
  /// `POST /api/v1/apps`, and skip this entirely - Mastodon itself supports that. But that's a
  /// client-side choice the Rellm protocol doesn't get involved in either way: this field only
  /// covers the admin-pre-registered path, which is what lets an app ID be shown/reused consistently
  /// across every client on this server rather than each one self-registering its own.)
  @$pb.TagNumber(4)
  $core.List<MastodonServer> get mastodonServers => $_getList(3);

  ///  If true, this server permits cross-server ("Sign in from...") federated auth to hand tokens to a
  ///  plaintext `http://localhost` frontend, for local development. Frontends should otherwise refuse
  ///  to send/receive federated auth tokens for `localhost`, and should show a warning to the user
  ///  whenever they do proceed. Unset (including on servers predating this field) means false.
  ///
  ///  Note this is only a frontend-enforced measure: the backend can't stop a modified client from
  ///  moving its own tokens wherever it likes.
  @$pb.TagNumber(5)
  $core.bool get unsecureLocalhostFederatedAuthEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set unsecureLocalhostFederatedAuthEnabled($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUnsecureLocalhostFederatedAuthEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearUnsecureLocalhostFederatedAuthEnabled() => clearField(5);
}

/// A server that this server will federate with.
class FederatedServer extends $pb.GeneratedMessage {
  factory FederatedServer({
    $core.String? host,
    $core.bool? configuredByDefault,
    $core.bool? pinnedByDefault,
  }) {
    final $result = create();
    if (host != null) {
      $result.host = host;
    }
    if (configuredByDefault != null) {
      $result.configuredByDefault = configuredByDefault;
    }
    if (pinnedByDefault != null) {
      $result.pinnedByDefault = pinnedByDefault;
    }
    return $result;
  }
  FederatedServer._() : super();
  factory FederatedServer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FederatedServer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FederatedServer', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'host')
    ..aOB(2, _omitFieldNames ? '' : 'configuredByDefault')
    ..aOB(3, _omitFieldNames ? '' : 'pinnedByDefault')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FederatedServer clone() => FederatedServer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FederatedServer copyWith(void Function(FederatedServer) updates) => super.copyWith((message) => updates(message as FederatedServer)) as FederatedServer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FederatedServer create() => FederatedServer._();
  FederatedServer createEmptyInstance() => create();
  static $pb.PbList<FederatedServer> createRepeated() => $pb.PbList<FederatedServer>();
  @$core.pragma('dart2js:noInline')
  static FederatedServer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FederatedServer>(create);
  static FederatedServer? _defaultInstance;

  /// The DNS hostname of the server to federate with.
  @$pb.TagNumber(1)
  $core.String get host => $_getSZ(0);
  @$pb.TagNumber(1)
  set host($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHost() => $_has(0);
  @$pb.TagNumber(1)
  void clearHost() => clearField(1);

  /// Indicates to UI clients that they should enable/configure the indicated server by default.
  @$pb.TagNumber(2)
  $core.bool get configuredByDefault => $_getBF(1);
  @$pb.TagNumber(2)
  set configuredByDefault($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfiguredByDefault() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfiguredByDefault() => clearField(2);

  /// Indicates to UI clients that they should pin the indicated server by default
  /// (showing its Events and Posts alongside the "main" server).
  @$pb.TagNumber(3)
  $core.bool get pinnedByDefault => $_getBF(2);
  @$pb.TagNumber(3)
  set pinnedByDefault($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPinnedByDefault() => $_has(2);
  @$pb.TagNumber(3)
  void clearPinnedByDefault() => clearField(3);
}

/// Some user on a Rellm server.
/// Most commonly a different server than the one serving up FederatedAccount data,
/// but users may also federate multiple accounts on the same server.
class FederatedAccount extends $pb.GeneratedMessage {
  factory FederatedAccount({
    $core.String? host,
    $core.String? userId,
  }) {
    final $result = create();
    if (host != null) {
      $result.host = host;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    return $result;
  }
  FederatedAccount._() : super();
  factory FederatedAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FederatedAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FederatedAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'host')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FederatedAccount clone() => FederatedAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FederatedAccount copyWith(void Function(FederatedAccount) updates) => super.copyWith((message) => updates(message as FederatedAccount)) as FederatedAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FederatedAccount create() => FederatedAccount._();
  FederatedAccount createEmptyInstance() => create();
  static $pb.PbList<FederatedAccount> createRepeated() => $pb.PbList<FederatedAccount>();
  @$core.pragma('dart2js:noInline')
  static FederatedAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FederatedAccount>(create);
  static FederatedAccount? _defaultInstance;

  /// The DNS hostname of the server that this user is on.
  @$pb.TagNumber(1)
  $core.String get host => $_getSZ(0);
  @$pb.TagNumber(1)
  set host($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHost() => $_has(0);
  @$pb.TagNumber(1)
  void clearHost() => clearField(1);

  /// The user ID of the user on the server.
  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);
}

/// Facebook authentication configuration for the server.
class FacebookAuthConfig extends $pb.GeneratedMessage {
  factory FacebookAuthConfig({
    $core.String? appId,
    $core.String? appSecret,
  }) {
    final $result = create();
    if (appId != null) {
      $result.appId = appId;
    }
    if (appSecret != null) {
      $result.appSecret = appSecret;
    }
    return $result;
  }
  FacebookAuthConfig._() : super();
  factory FacebookAuthConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FacebookAuthConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FacebookAuthConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'appId')
    ..aOS(2, _omitFieldNames ? '' : 'appSecret')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FacebookAuthConfig clone() => FacebookAuthConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FacebookAuthConfig copyWith(void Function(FacebookAuthConfig) updates) => super.copyWith((message) => updates(message as FacebookAuthConfig)) as FacebookAuthConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FacebookAuthConfig create() => FacebookAuthConfig._();
  FacebookAuthConfig createEmptyInstance() => create();
  static $pb.PbList<FacebookAuthConfig> createRepeated() => $pb.PbList<FacebookAuthConfig>();
  @$core.pragma('dart2js:noInline')
  static FacebookAuthConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FacebookAuthConfig>(create);
  static FacebookAuthConfig? _defaultInstance;

  /// The Facebook App ID for the server.
  @$pb.TagNumber(1)
  $core.String get appId => $_getSZ(0);
  @$pb.TagNumber(1)
  set appId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAppId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAppId() => clearField(1);

  /// The Facebook App Secret for the server. *Never serialized to the client.*
  /// Admins: Edit this in the database's JSONB column directly.
  @$pb.TagNumber(2)
  $core.String get appSecret => $_getSZ(1);
  @$pb.TagNumber(2)
  set appSecret($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAppSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearAppSecret() => clearField(2);
}

/// X (Twitter) authentication configuration for the server. See `FederationInfo.x_twitter_auth_config`.
class XTwitterAuthConfig extends $pb.GeneratedMessage {
  factory XTwitterAuthConfig({
    $core.String? clientId,
    $core.String? clientSecret,
  }) {
    final $result = create();
    if (clientId != null) {
      $result.clientId = clientId;
    }
    if (clientSecret != null) {
      $result.clientSecret = clientSecret;
    }
    return $result;
  }
  XTwitterAuthConfig._() : super();
  factory XTwitterAuthConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory XTwitterAuthConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'XTwitterAuthConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'clientId')
    ..aOS(2, _omitFieldNames ? '' : 'clientSecret')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  XTwitterAuthConfig clone() => XTwitterAuthConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  XTwitterAuthConfig copyWith(void Function(XTwitterAuthConfig) updates) => super.copyWith((message) => updates(message as XTwitterAuthConfig)) as XTwitterAuthConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static XTwitterAuthConfig create() => XTwitterAuthConfig._();
  XTwitterAuthConfig createEmptyInstance() => create();
  static $pb.PbList<XTwitterAuthConfig> createRepeated() => $pb.PbList<XTwitterAuthConfig>();
  @$core.pragma('dart2js:noInline')
  static XTwitterAuthConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<XTwitterAuthConfig>(create);
  static XTwitterAuthConfig? _defaultInstance;

  /// The X Developer App's Client ID for the server.
  @$pb.TagNumber(1)
  $core.String get clientId => $_getSZ(0);
  @$pb.TagNumber(1)
  set clientId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasClientId() => $_has(0);
  @$pb.TagNumber(1)
  void clearClientId() => clearField(1);

  /// The X Developer App's Client Secret for the server. *Never serialized to the client.*
  /// Admins: Edit this in the database's JSONB column directly.
  @$pb.TagNumber(2)
  $core.String get clientSecret => $_getSZ(1);
  @$pb.TagNumber(2)
  set clientSecret($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasClientSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientSecret() => clearField(2);
}

/// A Mastodon instance this server has a registered OAuth app on. See `FederationInfo.mastodon_servers`.
class MastodonServer extends $pb.GeneratedMessage {
  factory MastodonServer({
    $core.String? domain,
    $core.String? appId,
    $core.String? appSecret,
    $core.bool? configuredByDefault,
    $core.bool? pinnedByDefault,
  }) {
    final $result = create();
    if (domain != null) {
      $result.domain = domain;
    }
    if (appId != null) {
      $result.appId = appId;
    }
    if (appSecret != null) {
      $result.appSecret = appSecret;
    }
    if (configuredByDefault != null) {
      $result.configuredByDefault = configuredByDefault;
    }
    if (pinnedByDefault != null) {
      $result.pinnedByDefault = pinnedByDefault;
    }
    return $result;
  }
  MastodonServer._() : super();
  factory MastodonServer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MastodonServer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MastodonServer', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'domain')
    ..aOS(2, _omitFieldNames ? '' : 'appId')
    ..aOS(3, _omitFieldNames ? '' : 'appSecret')
    ..aOB(4, _omitFieldNames ? '' : 'configuredByDefault')
    ..aOB(5, _omitFieldNames ? '' : 'pinnedByDefault')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MastodonServer clone() => MastodonServer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MastodonServer copyWith(void Function(MastodonServer) updates) => super.copyWith((message) => updates(message as MastodonServer)) as MastodonServer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MastodonServer create() => MastodonServer._();
  MastodonServer createEmptyInstance() => create();
  static $pb.PbList<MastodonServer> createRepeated() => $pb.PbList<MastodonServer>();
  @$core.pragma('dart2js:noInline')
  static MastodonServer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MastodonServer>(create);
  static MastodonServer? _defaultInstance;

  /// The Mastodon instance's hostname, e.g. "mastodon.social".
  @$pb.TagNumber(1)
  $core.String get domain => $_getSZ(0);
  @$pb.TagNumber(1)
  set domain($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDomain() => $_has(0);
  @$pb.TagNumber(1)
  void clearDomain() => clearField(1);

  /// The registered app's Client ID for this instance. Safe to serialize to clients - used
  /// directly to build the instance's `/oauth/authorize` URL, the same way `FacebookAuthConfig.app_id`/
  /// `XTwitterAuthConfig.client_id` are.
  @$pb.TagNumber(2)
  $core.String get appId => $_getSZ(1);
  @$pb.TagNumber(2)
  set appId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAppId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAppId() => clearField(2);

  /// The registered app's Client Secret for this instance. *Never serialized to the client.*
  /// Admins: Edit this in the database's JSONB column directly. Used server-side to exchange an
  /// authorization code for an access token once a user completes the OAuth popup.
  @$pb.TagNumber(3)
  $core.String get appSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set appSecret($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAppSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearAppSecret() => clearField(3);

  /// Indicates to UI clients that they should browse the indicated instance's public timeline by
  /// default (added to it with no OAuth/account needed at all - see this message's own doc on the
  /// difference between browsing and connecting).
  @$pb.TagNumber(4)
  $core.bool get configuredByDefault => $_getBF(3);
  @$pb.TagNumber(4)
  set configuredByDefault($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfiguredByDefault() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiguredByDefault() => clearField(4);

  /// Indicates to UI clients that they should pin the indicated instance by default (showing its
  /// Posts alongside the "main" server). Currently has the same effect as `configured_by_default`
  /// - as of this writing, clients have no "added but not shown" state for a browsed instance the
  /// way `FederatedServer.pinned_by_default`'s `Server.enabled` does, so there's nothing for this
  /// to mean *in addition to* `configured_by_default`. Kept as its own field for symmetry with
  /// `FederatedServer`, and in case that changes.
  @$pb.TagNumber(5)
  $core.bool get pinnedByDefault => $_getBF(4);
  @$pb.TagNumber(5)
  set pinnedByDefault($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPinnedByDefault() => $_has(4);
  @$pb.TagNumber(5)
  void clearPinnedByDefault() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
