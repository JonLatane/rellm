//
//  Generated code. Do not modify.
//  source: sync.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/timestamp.pb.dart' as $13;
import 'media.pb.dart' as $5;

enum SyncDestination_Configuration {
  facebookPage, 
  instagramAccount, 
  mastodonAccount, 
  blueskyAccount, 
  xTwitterAccount, 
  threadsAccount, 
  notSet
}

/// A user-owned destination to sync (cross-post) content out to. Mirrors [`SyncSource`](#rellm-SyncSource),
/// but for pushing content out rather than pulling content in. Originally Event-specific
/// (as `EventSyncDestination`), now shared by both [`Occasion`](#rellm-Occasion)s (see `events.proto`'s
/// [`SyncOccasionRequest`](#rellm-SyncOccasionRequest)) and [`Post`](#rellm-Post)s (see `posts.proto`'s [`SyncPostRequest`](#rellm-SyncPostRequest)).
class SyncDestination extends $pb.GeneratedMessage {
  factory SyncDestination({
    $core.String? id,
    $5.Author? owner,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
    $fixnum.Int64? syncedOccasionCount,
    $fixnum.Int64? syncedPostCount,
    FacebookPage? facebookPage,
    InstagramAccount? instagramAccount,
    MastodonAccount? mastodonAccount,
    BlueskyAccount? blueskyAccount,
    XTwitterAccount? xTwitterAccount,
    ThreadsAccount? threadsAccount,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (owner != null) {
      $result.owner = owner;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    if (syncedOccasionCount != null) {
      $result.syncedOccasionCount = syncedOccasionCount;
    }
    if (syncedPostCount != null) {
      $result.syncedPostCount = syncedPostCount;
    }
    if (facebookPage != null) {
      $result.facebookPage = facebookPage;
    }
    if (instagramAccount != null) {
      $result.instagramAccount = instagramAccount;
    }
    if (mastodonAccount != null) {
      $result.mastodonAccount = mastodonAccount;
    }
    if (blueskyAccount != null) {
      $result.blueskyAccount = blueskyAccount;
    }
    if (xTwitterAccount != null) {
      $result.xTwitterAccount = xTwitterAccount;
    }
    if (threadsAccount != null) {
      $result.threadsAccount = threadsAccount;
    }
    return $result;
  }
  SyncDestination._() : super();
  factory SyncDestination.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SyncDestination.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, SyncDestination_Configuration> _SyncDestination_ConfigurationByTag = {
    9 : SyncDestination_Configuration.facebookPage,
    10 : SyncDestination_Configuration.instagramAccount,
    11 : SyncDestination_Configuration.mastodonAccount,
    12 : SyncDestination_Configuration.blueskyAccount,
    13 : SyncDestination_Configuration.xTwitterAccount,
    14 : SyncDestination_Configuration.threadsAccount,
    0 : SyncDestination_Configuration.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SyncDestination', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [9, 10, 11, 12, 13, 14])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'owner', subBuilder: $5.Author.create)
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(5, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'syncedOccasionCount', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'syncedPostCount', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<FacebookPage>(9, _omitFieldNames ? '' : 'facebookPage', subBuilder: FacebookPage.create)
    ..aOM<InstagramAccount>(10, _omitFieldNames ? '' : 'instagramAccount', subBuilder: InstagramAccount.create)
    ..aOM<MastodonAccount>(11, _omitFieldNames ? '' : 'mastodonAccount', subBuilder: MastodonAccount.create)
    ..aOM<BlueskyAccount>(12, _omitFieldNames ? '' : 'blueskyAccount', subBuilder: BlueskyAccount.create)
    ..aOM<XTwitterAccount>(13, _omitFieldNames ? '' : 'xTwitterAccount', subBuilder: XTwitterAccount.create)
    ..aOM<ThreadsAccount>(14, _omitFieldNames ? '' : 'threadsAccount', subBuilder: ThreadsAccount.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SyncDestination clone() => SyncDestination()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SyncDestination copyWith(void Function(SyncDestination) updates) => super.copyWith((message) => updates(message as SyncDestination)) as SyncDestination;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncDestination create() => SyncDestination._();
  SyncDestination createEmptyInstance() => create();
  static $pb.PbList<SyncDestination> createRepeated() => $pb.PbList<SyncDestination>();
  @$core.pragma('dart2js:noInline')
  static SyncDestination getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncDestination>(create);
  static SyncDestination? _defaultInstance;

  SyncDestination_Configuration whichConfiguration() => _SyncDestination_ConfigurationByTag[$_whichOneof(0)]!;
  void clearConfiguration() => clearField($_whichOneof(0));

  /// Unique ID for the destination.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The user information for the owner of this destination.
  @$pb.TagNumber(2)
  $5.Author get owner => $_getN(1);
  @$pb.TagNumber(2)
  set owner($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwner() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwner() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureOwner() => $_ensure(1);

  /// The time the SyncDestination was created.
  @$pb.TagNumber(4)
  $13.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(4)
  set createdAt($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(4)
  void clearCreatedAt() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureCreatedAt() => $_ensure(2);

  /// The time the SyncDestination was last updated.
  @$pb.TagNumber(5)
  $13.Timestamp get updatedAt => $_getN(3);
  @$pb.TagNumber(5)
  set updatedAt($13.Timestamp v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasUpdatedAt() => $_has(3);
  @$pb.TagNumber(5)
  void clearUpdatedAt() => clearField(5);
  @$pb.TagNumber(5)
  $13.Timestamp ensureUpdatedAt() => $_ensure(3);

  /// The number of Occasions synced to this destination so far. Computed with a `COUNT` at
  /// request time (unlike [`SyncSource`](#rellm-SyncSource)'s `event_count`/`occasion_count`, which are
  /// recomputed-and-stored on each sync) since destinations are pushed to on demand, not synced
  /// in bulk on an interval.
  @$pb.TagNumber(6)
  $fixnum.Int64 get syncedOccasionCount => $_getI64(4);
  @$pb.TagNumber(6)
  set syncedOccasionCount($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(6)
  $core.bool hasSyncedOccasionCount() => $_has(4);
  @$pb.TagNumber(6)
  void clearSyncedOccasionCount() => clearField(6);

  /// The number of Posts synced to this destination so far. Computed the same way as
  /// `synced_occasion_count`, just against Posts instead of Occasions.
  @$pb.TagNumber(7)
  $fixnum.Int64 get syncedPostCount => $_getI64(5);
  @$pb.TagNumber(7)
  set syncedPostCount($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(7)
  $core.bool hasSyncedPostCount() => $_has(5);
  @$pb.TagNumber(7)
  void clearSyncedPostCount() => clearField(7);

  /// A connected Facebook Page to post Occasions/Posts to.
  @$pb.TagNumber(9)
  FacebookPage get facebookPage => $_getN(6);
  @$pb.TagNumber(9)
  set facebookPage(FacebookPage v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasFacebookPage() => $_has(6);
  @$pb.TagNumber(9)
  void clearFacebookPage() => clearField(9);
  @$pb.TagNumber(9)
  FacebookPage ensureFacebookPage() => $_ensure(6);

  /// A connected Instagram Business/Creator account to post Occasions/Posts to.
  @$pb.TagNumber(10)
  InstagramAccount get instagramAccount => $_getN(7);
  @$pb.TagNumber(10)
  set instagramAccount(InstagramAccount v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasInstagramAccount() => $_has(7);
  @$pb.TagNumber(10)
  void clearInstagramAccount() => clearField(10);
  @$pb.TagNumber(10)
  InstagramAccount ensureInstagramAccount() => $_ensure(7);

  /// A connected Mastodon account to post Occasions/Posts to.
  @$pb.TagNumber(11)
  MastodonAccount get mastodonAccount => $_getN(8);
  @$pb.TagNumber(11)
  set mastodonAccount(MastodonAccount v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasMastodonAccount() => $_has(8);
  @$pb.TagNumber(11)
  void clearMastodonAccount() => clearField(11);
  @$pb.TagNumber(11)
  MastodonAccount ensureMastodonAccount() => $_ensure(8);

  /// A connected Bluesky account to post Occasions/Posts to.
  @$pb.TagNumber(12)
  BlueskyAccount get blueskyAccount => $_getN(9);
  @$pb.TagNumber(12)
  set blueskyAccount(BlueskyAccount v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasBlueskyAccount() => $_has(9);
  @$pb.TagNumber(12)
  void clearBlueskyAccount() => clearField(12);
  @$pb.TagNumber(12)
  BlueskyAccount ensureBlueskyAccount() => $_ensure(9);

  /// A connected X (Twitter) account to post Occasions/Posts to.
  @$pb.TagNumber(13)
  XTwitterAccount get xTwitterAccount => $_getN(10);
  @$pb.TagNumber(13)
  set xTwitterAccount(XTwitterAccount v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasXTwitterAccount() => $_has(10);
  @$pb.TagNumber(13)
  void clearXTwitterAccount() => clearField(13);
  @$pb.TagNumber(13)
  XTwitterAccount ensureXTwitterAccount() => $_ensure(10);

  /// A connected Threads account to post Occasions/Posts to.
  @$pb.TagNumber(14)
  ThreadsAccount get threadsAccount => $_getN(11);
  @$pb.TagNumber(14)
  set threadsAccount(ThreadsAccount v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasThreadsAccount() => $_has(11);
  @$pb.TagNumber(14)
  void clearThreadsAccount() => clearField(14);
  @$pb.TagNumber(14)
  ThreadsAccount ensureThreadsAccount() => $_ensure(11);
}

/// Response to a request for the current user's [`SyncDestination`](#rellm-SyncDestination)s.
class GetSyncDestinationsResponse extends $pb.GeneratedMessage {
  factory GetSyncDestinationsResponse({
    $core.Iterable<SyncDestination>? destinations,
  }) {
    final $result = create();
    if (destinations != null) {
      $result.destinations.addAll(destinations);
    }
    return $result;
  }
  GetSyncDestinationsResponse._() : super();
  factory GetSyncDestinationsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetSyncDestinationsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetSyncDestinationsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<SyncDestination>(1, _omitFieldNames ? '' : 'destinations', $pb.PbFieldType.PM, subBuilder: SyncDestination.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetSyncDestinationsResponse clone() => GetSyncDestinationsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetSyncDestinationsResponse copyWith(void Function(GetSyncDestinationsResponse) updates) => super.copyWith((message) => updates(message as GetSyncDestinationsResponse)) as GetSyncDestinationsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSyncDestinationsResponse create() => GetSyncDestinationsResponse._();
  GetSyncDestinationsResponse createEmptyInstance() => create();
  static $pb.PbList<GetSyncDestinationsResponse> createRepeated() => $pb.PbList<GetSyncDestinationsResponse>();
  @$core.pragma('dart2js:noInline')
  static GetSyncDestinationsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetSyncDestinationsResponse>(create);
  static GetSyncDestinationsResponse? _defaultInstance;

  /// The current user's SyncDestinations.
  @$pb.TagNumber(1)
  $core.List<SyncDestination> get destinations => $_getList(0);
}

/// Request to delete a SyncDestination.
class DeleteSyncDestinationRequest extends $pb.GeneratedMessage {
  factory DeleteSyncDestinationRequest({
    SyncDestination? destination,
    $core.bool? deleteSyncedPosts,
  }) {
    final $result = create();
    if (destination != null) {
      $result.destination = destination;
    }
    if (deleteSyncedPosts != null) {
      $result.deleteSyncedPosts = deleteSyncedPosts;
    }
    return $result;
  }
  DeleteSyncDestinationRequest._() : super();
  factory DeleteSyncDestinationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeleteSyncDestinationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeleteSyncDestinationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<SyncDestination>(1, _omitFieldNames ? '' : 'destination', subBuilder: SyncDestination.create)
    ..aOB(2, _omitFieldNames ? '' : 'deleteSyncedPosts')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeleteSyncDestinationRequest clone() => DeleteSyncDestinationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeleteSyncDestinationRequest copyWith(void Function(DeleteSyncDestinationRequest) updates) => super.copyWith((message) => updates(message as DeleteSyncDestinationRequest)) as DeleteSyncDestinationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteSyncDestinationRequest create() => DeleteSyncDestinationRequest._();
  DeleteSyncDestinationRequest createEmptyInstance() => create();
  static $pb.PbList<DeleteSyncDestinationRequest> createRepeated() => $pb.PbList<DeleteSyncDestinationRequest>();
  @$core.pragma('dart2js:noInline')
  static DeleteSyncDestinationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteSyncDestinationRequest>(create);
  static DeleteSyncDestinationRequest? _defaultInstance;

  /// The destination to be deleted.
  @$pb.TagNumber(1)
  SyncDestination get destination => $_getN(0);
  @$pb.TagNumber(1)
  set destination(SyncDestination v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasDestination() => $_has(0);
  @$pb.TagNumber(1)
  void clearDestination() => clearField(1);
  @$pb.TagNumber(1)
  SyncDestination ensureDestination() => $_ensure(0);

  /// Whether to also delete posts already made on the destination (e.g. the Facebook Page posts).
  @$pb.TagNumber(2)
  $core.bool get deleteSyncedPosts => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteSyncedPosts($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeleteSyncedPosts() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteSyncedPosts() => clearField(2);
}

///  A Facebook Page connected as a [`SyncDestination`](#rellm-SyncDestination) - **never a personal profile**. Facebook
///  deprecated the `publish_actions` permission in 2018, which was the only way any third-party app
///  could ever post to a personal timeline; there's no Graph API call today, for any app, that can
///  post anything (feed post, photo, or otherwise) to a personal profile on a user's behalf. A Page
///  is the only kind of Facebook entity a self-hosted server like this can post to at all - this
///  isn't a Rellm design choice to work around, it's a hard platform restriction. (Unrelated to
///  this: Facebook *Events* specifically are also unreachable, even for Pages - see
///  `docs/facebook_and_x_twitter_federation.md`'s "It posts to the Page's feed, not a real Facebook
///  Event" for that separate, independent 2018-era lockdown.)
///
///  Media limitation: a synced Post/Occasion's attached video and images are mutually
///  exclusive on Facebook - if both are present, the video is posted and any images are silently
///  dropped (Facebook Pages can't attach both to a single feed post).
class FacebookPage extends $pb.GeneratedMessage {
  factory FacebookPage({
    $core.String? pageId,
    $core.String? pageName,
    $core.String? shortLivedUserAccessToken,
  }) {
    final $result = create();
    if (pageId != null) {
      $result.pageId = pageId;
    }
    if (pageName != null) {
      $result.pageName = pageName;
    }
    if (shortLivedUserAccessToken != null) {
      $result.shortLivedUserAccessToken = shortLivedUserAccessToken;
    }
    return $result;
  }
  FacebookPage._() : super();
  factory FacebookPage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FacebookPage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FacebookPage', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'pageId')
    ..aOS(2, _omitFieldNames ? '' : 'pageName')
    ..aOS(3, _omitFieldNames ? '' : 'shortLivedUserAccessToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FacebookPage clone() => FacebookPage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FacebookPage copyWith(void Function(FacebookPage) updates) => super.copyWith((message) => updates(message as FacebookPage)) as FacebookPage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FacebookPage create() => FacebookPage._();
  FacebookPage createEmptyInstance() => create();
  static $pb.PbList<FacebookPage> createRepeated() => $pb.PbList<FacebookPage>();
  @$core.pragma('dart2js:noInline')
  static FacebookPage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FacebookPage>(create);
  static FacebookPage? _defaultInstance;

  /// The Facebook Page's ID.
  @$pb.TagNumber(1)
  $core.String get pageId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pageId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageId() => clearField(1);

  /// The Facebook Page's name, populated by the server when the connection is made.
  @$pb.TagNumber(2)
  $core.String get pageName => $_getSZ(1);
  @$pb.TagNumber(2)
  set pageName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPageName() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageName() => clearField(2);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): a short-lived user access token
  /// from client-side Facebook Login, exchanged server-side for a long-lived Page access token.
  /// Never populated in responses.
  @$pb.TagNumber(3)
  $core.String get shortLivedUserAccessToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set shortLivedUserAccessToken($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasShortLivedUserAccessToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearShortLivedUserAccessToken() => clearField(3);
}

///  An Instagram Business/Creator account connected as a [`SyncDestination`](#rellm-SyncDestination) - **never a personal
///  Instagram account**. Unlike [`FacebookPage`](#rellm-FacebookPage)'s restriction (a *deprecated* permission that used to let
///  apps post to a personal timeline), this one was never possible in the first place: Instagram's
///  Content Publishing API was built from the start only for professional (Business/Creator)
///  accounts, so a personal Instagram account simply has no API surface to post to at all,
///  regardless of what this server does. Posting to Instagram also requires the professional account
///  to be linked to a Facebook Page, so this reuses the same Facebook Login popup and app credentials
///  as [`FacebookPage`](#rellm-FacebookPage) - the server exchanges the token for the Page's access token, then looks up
///  that Page's linked Instagram Business account.
///
///  Media limitation: only the *first* attached image/video on a synced Post/Occasion is
///  posted - no carousel/multi-image support yet. A post with no media at all is rejected
///  (`instagram_requires_media`) - Instagram's Graph API has no text-only post type.
class InstagramAccount extends $pb.GeneratedMessage {
  factory InstagramAccount({
    $core.String? instagramBusinessAccountId,
    $core.String? username,
    $core.String? pageId,
    $core.String? shortLivedUserAccessToken,
  }) {
    final $result = create();
    if (instagramBusinessAccountId != null) {
      $result.instagramBusinessAccountId = instagramBusinessAccountId;
    }
    if (username != null) {
      $result.username = username;
    }
    if (pageId != null) {
      $result.pageId = pageId;
    }
    if (shortLivedUserAccessToken != null) {
      $result.shortLivedUserAccessToken = shortLivedUserAccessToken;
    }
    return $result;
  }
  InstagramAccount._() : super();
  factory InstagramAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory InstagramAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'InstagramAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'instagramBusinessAccountId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'pageId')
    ..aOS(4, _omitFieldNames ? '' : 'shortLivedUserAccessToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  InstagramAccount clone() => InstagramAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  InstagramAccount copyWith(void Function(InstagramAccount) updates) => super.copyWith((message) => updates(message as InstagramAccount)) as InstagramAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InstagramAccount create() => InstagramAccount._();
  InstagramAccount createEmptyInstance() => create();
  static $pb.PbList<InstagramAccount> createRepeated() => $pb.PbList<InstagramAccount>();
  @$core.pragma('dart2js:noInline')
  static InstagramAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InstagramAccount>(create);
  static InstagramAccount? _defaultInstance;

  /// The Instagram Business/Creator account's ID, used for all Graph API posting calls.
  @$pb.TagNumber(1)
  $core.String get instagramBusinessAccountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set instagramBusinessAccountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasInstagramBusinessAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstagramBusinessAccountId() => clearField(1);

  /// The Instagram account's @username, populated by the server when the connection is made.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// The linked Facebook Page's ID, kept for reference/reconnect.
  @$pb.TagNumber(3)
  $core.String get pageId => $_getSZ(2);
  @$pb.TagNumber(3)
  set pageId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPageId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPageId() => clearField(3);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): a short-lived user access token
  /// from client-side Facebook Login (same flow as [`FacebookPage`](#rellm-FacebookPage)), exchanged server-side for a
  /// long-lived Page access token, which is also used to post to the linked Instagram account.
  /// Never populated in responses.
  @$pb.TagNumber(4)
  $core.String get shortLivedUserAccessToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set shortLivedUserAccessToken($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasShortLivedUserAccessToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearShortLivedUserAccessToken() => clearField(4);
}

///  A Mastodon account connected as a [`SyncDestination`](#rellm-SyncDestination) via a user-supplied Personal Access Token
///  (generated on the user's own instance, under Preferences > Development), rather than an OAuth
///  popup - Mastodon instances are user-chosen arbitrary domains, so there's no single app to
///  register ahead of time the way Facebook/Instagram have one.
///
///  Media: up to 4 attached images/videos on a synced Post/Occasion are downloaded and
///  re-uploaded as real Mastodon media attachments (any mix of image/video types); a failed
///  individual upload is skipped rather than failing the whole post.
class MastodonAccount extends $pb.GeneratedMessage {
  factory MastodonAccount({
    $core.String? instanceHost,
    $core.String? username,
    $core.String? accessToken,
  }) {
    final $result = create();
    if (instanceHost != null) {
      $result.instanceHost = instanceHost;
    }
    if (username != null) {
      $result.username = username;
    }
    if (accessToken != null) {
      $result.accessToken = accessToken;
    }
    return $result;
  }
  MastodonAccount._() : super();
  factory MastodonAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MastodonAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MastodonAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'instanceHost')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'accessToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MastodonAccount clone() => MastodonAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MastodonAccount copyWith(void Function(MastodonAccount) updates) => super.copyWith((message) => updates(message as MastodonAccount)) as MastodonAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MastodonAccount create() => MastodonAccount._();
  MastodonAccount createEmptyInstance() => create();
  static $pb.PbList<MastodonAccount> createRepeated() => $pb.PbList<MastodonAccount>();
  @$core.pragma('dart2js:noInline')
  static MastodonAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MastodonAccount>(create);
  static MastodonAccount? _defaultInstance;

  /// The Mastodon instance's hostname, e.g. "mastodon.social".
  @$pb.TagNumber(1)
  $core.String get instanceHost => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceHost($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasInstanceHost() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceHost() => clearField(1);

  /// The account's username on that instance, populated by the server when the connection is made.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination)/[`UpdateSyncDestination`](#grpc-api-UpdateSyncDestination): the user's own
  /// Personal Access Token for `instance_host`. Never populated in responses.
  @$pb.TagNumber(3)
  $core.String get accessToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set accessToken($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAccessToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccessToken() => clearField(3);
}

///  A Bluesky (AT Protocol) account connected as a [`SyncDestination`](#rellm-SyncDestination) via an "App Password"
///  (generated at Settings > App Passwords - not the account's main password), rather than an
///  OAuth popup.
///
///  Media limitation: only attached *images* on a synced Post/Occasion are posted (up to 4,
///  downloaded and re-uploaded as Bluesky blobs) - video is silently dropped entirely. Bluesky
///  video embeds need a separate, more complex upload-and-processing flow not yet built.
class BlueskyAccount extends $pb.GeneratedMessage {
  factory BlueskyAccount({
    $core.String? handle,
    $core.String? did,
    $core.String? appPassword,
  }) {
    final $result = create();
    if (handle != null) {
      $result.handle = handle;
    }
    if (did != null) {
      $result.did = did;
    }
    if (appPassword != null) {
      $result.appPassword = appPassword;
    }
    return $result;
  }
  BlueskyAccount._() : super();
  factory BlueskyAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BlueskyAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BlueskyAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handle')
    ..aOS(2, _omitFieldNames ? '' : 'did')
    ..aOS(3, _omitFieldNames ? '' : 'appPassword')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BlueskyAccount clone() => BlueskyAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BlueskyAccount copyWith(void Function(BlueskyAccount) updates) => super.copyWith((message) => updates(message as BlueskyAccount)) as BlueskyAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BlueskyAccount create() => BlueskyAccount._();
  BlueskyAccount createEmptyInstance() => create();
  static $pb.PbList<BlueskyAccount> createRepeated() => $pb.PbList<BlueskyAccount>();
  @$core.pragma('dart2js:noInline')
  static BlueskyAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BlueskyAccount>(create);
  static BlueskyAccount? _defaultInstance;

  /// The account's handle, e.g. "jon.bsky.social".
  @$pb.TagNumber(1)
  $core.String get handle => $_getSZ(0);
  @$pb.TagNumber(1)
  set handle($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandle() => clearField(1);

  /// The account's DID (decentralized identifier), populated by the server when the connection is
  /// made.
  @$pb.TagNumber(2)
  $core.String get did => $_getSZ(1);
  @$pb.TagNumber(2)
  set did($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDid() => $_has(1);
  @$pb.TagNumber(2)
  void clearDid() => clearField(2);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination)/[`UpdateSyncDestination`](#grpc-api-UpdateSyncDestination): the user's own
  /// App Password. Never populated in responses. Sessions are created fresh per post rather than
  /// stored/refreshed, since App Passwords don't expire.
  @$pb.TagNumber(3)
  $core.String get appPassword => $_getSZ(2);
  @$pb.TagNumber(3)
  set appPassword($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAppPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearAppPassword() => clearField(3);
}

///  An X (Twitter) account connected as a [`SyncDestination`](#rellm-SyncDestination), via an OAuth 2.0 Authorization Code +
///  PKCE flow at x.com. Requires this server to have a registered X Developer App configured (see
///  `FederationInfo.x_twitter_auth_config`) - every RPC touching an `XTwitterAccount` destination
///  fails with `x_twitter_app_not_configured` until an admin sets one, mirroring
///  [`FacebookAuthConfig`](#rellm-FacebookAuthConfig)/`facebook_app_not_configured`. Unlike Facebook/Instagram/Threads (which reuse one
///  Meta App), an admin registers this app once and every user on the server connects their own X
///  account through it - no per-user API keys needed.
///
///  Media limitation: up to 4 attached *images* on a synced Post/Occasion are downloaded and
///  re-uploaded via X's media upload endpoint. Video is not yet supported - X's video upload
///  requires a chunked upload-and-processing flow (mirroring Bluesky's own documented video gap)
///  not yet built; a video attachment is silently skipped.
class XTwitterAccount extends $pb.GeneratedMessage {
  factory XTwitterAccount({
    $core.String? username,
    $core.String? xUserId,
    $core.String? authorizationCode,
    $core.String? codeVerifier,
  }) {
    final $result = create();
    if (username != null) {
      $result.username = username;
    }
    if (xUserId != null) {
      $result.xUserId = xUserId;
    }
    if (authorizationCode != null) {
      $result.authorizationCode = authorizationCode;
    }
    if (codeVerifier != null) {
      $result.codeVerifier = codeVerifier;
    }
    return $result;
  }
  XTwitterAccount._() : super();
  factory XTwitterAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory XTwitterAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'XTwitterAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'xUserId')
    ..aOS(4, _omitFieldNames ? '' : 'authorizationCode')
    ..aOS(5, _omitFieldNames ? '' : 'codeVerifier')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  XTwitterAccount clone() => XTwitterAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  XTwitterAccount copyWith(void Function(XTwitterAccount) updates) => super.copyWith((message) => updates(message as XTwitterAccount)) as XTwitterAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static XTwitterAccount create() => XTwitterAccount._();
  XTwitterAccount createEmptyInstance() => create();
  static $pb.PbList<XTwitterAccount> createRepeated() => $pb.PbList<XTwitterAccount>();
  @$core.pragma('dart2js:noInline')
  static XTwitterAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<XTwitterAccount>(create);
  static XTwitterAccount? _defaultInstance;

  /// The account's @username, populated by the server when the connection is made.
  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => clearField(1);

  /// The account's numeric X user ID, populated by the server when the connection is made.
  @$pb.TagNumber(3)
  $core.String get xUserId => $_getSZ(1);
  @$pb.TagNumber(3)
  set xUserId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasXUserId() => $_has(1);
  @$pb.TagNumber(3)
  void clearXUserId() => clearField(3);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the OAuth authorization code from the
  /// X login popup. Never populated in responses.
  @$pb.TagNumber(4)
  $core.String get authorizationCode => $_getSZ(2);
  @$pb.TagNumber(4)
  set authorizationCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasAuthorizationCode() => $_has(2);
  @$pb.TagNumber(4)
  void clearAuthorizationCode() => clearField(4);

  /// Only used (and required, alongside `authorization_code`) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the PKCE
  /// code verifier the popup generated before sending its paired `code_challenge` to X's authorize
  /// endpoint. X mandates PKCE (unlike Threads/Facebook's plain code exchange), so the server needs
  /// this to complete the token exchange. Never populated in responses.
  @$pb.TagNumber(5)
  $core.String get codeVerifier => $_getSZ(3);
  @$pb.TagNumber(5)
  set codeVerifier($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(5)
  $core.bool hasCodeVerifier() => $_has(3);
  @$pb.TagNumber(5)
  void clearCodeVerifier() => clearField(5);
}

///  A connected Threads account - **a genuinely personal account works fine here**, unlike
///  [`FacebookPage`](#rellm-FacebookPage)/[`InstagramAccount`](#rellm-InstagramAccount): the Threads API (a separate product from Instagram's,
///  launched 2024) has no Page-linkage or Business/Creator-account requirement at all - Threads
///  OAuth directly authorizes whatever single Threads account the user logs in with, personal or
///  not. It's still a product added to this server's existing Meta App (see [`FacebookAuthConfig`](#rellm-FacebookAuthConfig))
///  rather than a separately-registered app, so no separate auth config is needed. Unlike
///  [`FacebookPage`](#rellm-FacebookPage)/[`InstagramAccount`](#rellm-InstagramAccount), connecting one is a `response_type=code` OAuth flow at
///  threads.net (not facebook.com) with no "choose a Page" step - the code is exchanged server-side
///  for a short-lived token, then a long-lived one (~60 day expiry, refreshable via
///  `grant_type=th_refresh_token` - not yet implemented; a connected destination will need
///  reconnecting after ~60 days until a refresh job exists).
///
///  Media limitation: only the *first* attached image/video on a synced Post/Occasion is
///  posted - no carousel/multi-image support yet. Unlike [`InstagramAccount`](#rellm-InstagramAccount), a text-only post
///  (no media at all) is valid.
class ThreadsAccount extends $pb.GeneratedMessage {
  factory ThreadsAccount({
    $core.String? threadsUserId,
    $core.String? username,
    $core.String? authorizationCode,
  }) {
    final $result = create();
    if (threadsUserId != null) {
      $result.threadsUserId = threadsUserId;
    }
    if (username != null) {
      $result.username = username;
    }
    if (authorizationCode != null) {
      $result.authorizationCode = authorizationCode;
    }
    return $result;
  }
  ThreadsAccount._() : super();
  factory ThreadsAccount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ThreadsAccount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ThreadsAccount', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'threadsUserId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'authorizationCode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ThreadsAccount clone() => ThreadsAccount()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ThreadsAccount copyWith(void Function(ThreadsAccount) updates) => super.copyWith((message) => updates(message as ThreadsAccount)) as ThreadsAccount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ThreadsAccount create() => ThreadsAccount._();
  ThreadsAccount createEmptyInstance() => create();
  static $pb.PbList<ThreadsAccount> createRepeated() => $pb.PbList<ThreadsAccount>();
  @$core.pragma('dart2js:noInline')
  static ThreadsAccount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ThreadsAccount>(create);
  static ThreadsAccount? _defaultInstance;

  /// The account's Threads user ID, used for all posting calls.
  @$pb.TagNumber(1)
  $core.String get threadsUserId => $_getSZ(0);
  @$pb.TagNumber(1)
  set threadsUserId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasThreadsUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearThreadsUserId() => clearField(1);

  /// The account's @username, populated by the server when the connection is made.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// Only used (and required) on [`CreateSyncDestination`](#grpc-api-CreateSyncDestination): the OAuth authorization code from the
  /// Threads login popup. Never populated in responses.
  @$pb.TagNumber(3)
  $core.String get authorizationCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set authorizationCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAuthorizationCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthorizationCode() => clearField(3);
}

/// The status of a single piece of content's (an [`Occasion`](#rellm-Occasion) or [`Post`](#rellm-Post)) sync (cross-post) to
/// one [`SyncDestination`](#rellm-SyncDestination). Shared/generic so both `Occasion.sync_destinations` and
/// `Post.sync_destinations` can reuse it.
class SyncDestinationStatus extends $pb.GeneratedMessage {
  factory SyncDestinationStatus({
    $core.String? syncDestinationId,
    $core.String? destinationInstanceId,
    $core.String? destinationUrl,
    $13.Timestamp? syncedAt,
  }) {
    final $result = create();
    if (syncDestinationId != null) {
      $result.syncDestinationId = syncDestinationId;
    }
    if (destinationInstanceId != null) {
      $result.destinationInstanceId = destinationInstanceId;
    }
    if (destinationUrl != null) {
      $result.destinationUrl = destinationUrl;
    }
    if (syncedAt != null) {
      $result.syncedAt = syncedAt;
    }
    return $result;
  }
  SyncDestinationStatus._() : super();
  factory SyncDestinationStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SyncDestinationStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SyncDestinationStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'syncDestinationId')
    ..aOS(2, _omitFieldNames ? '' : 'destinationInstanceId')
    ..aOS(3, _omitFieldNames ? '' : 'destinationUrl')
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'syncedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SyncDestinationStatus clone() => SyncDestinationStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SyncDestinationStatus copyWith(void Function(SyncDestinationStatus) updates) => super.copyWith((message) => updates(message as SyncDestinationStatus)) as SyncDestinationStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncDestinationStatus create() => SyncDestinationStatus._();
  SyncDestinationStatus createEmptyInstance() => create();
  static $pb.PbList<SyncDestinationStatus> createRepeated() => $pb.PbList<SyncDestinationStatus>();
  @$core.pragma('dart2js:noInline')
  static SyncDestinationStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncDestinationStatus>(create);
  static SyncDestinationStatus? _defaultInstance;

  /// The SyncDestination this status is for.
  @$pb.TagNumber(1)
  $core.String get syncDestinationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set syncDestinationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSyncDestinationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSyncDestinationId() => clearField(1);

  /// The ID of the resulting post on the destination (e.g. a Facebook Post ID).
  @$pb.TagNumber(2)
  $core.String get destinationInstanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set destinationInstanceId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDestinationInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestinationInstanceId() => clearField(2);

  /// A link to the resulting post on the destination, if available.
  @$pb.TagNumber(3)
  $core.String get destinationUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set destinationUrl($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDestinationUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearDestinationUrl() => clearField(3);

  /// The time this content was last successfully synced to the destination.
  @$pb.TagNumber(4)
  $13.Timestamp get syncedAt => $_getN(3);
  @$pb.TagNumber(4)
  set syncedAt($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasSyncedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearSyncedAt() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureSyncedAt() => $_ensure(3);
}

enum SyncSource_Configuration {
  icsSubscriptionUrl, 
  rssSubscriptionUrl, 
  atomSubscriptionUrl, 
  notSet
}

/// A user-owned source to sync events from.
class SyncSource extends $pb.GeneratedMessage {
  factory SyncSource({
    $core.String? id,
    $5.Author? owner,
    $fixnum.Int64? syncIntervalSeconds,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
    $13.Timestamp? lastSyncedAt,
    $fixnum.Int64? eventCount,
    $fixnum.Int64? occasionCount,
    $core.String? icsSubscriptionUrl,
    $fixnum.Int64? postCount,
    $core.String? rssSubscriptionUrl,
    $core.String? atomSubscriptionUrl,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (owner != null) {
      $result.owner = owner;
    }
    if (syncIntervalSeconds != null) {
      $result.syncIntervalSeconds = syncIntervalSeconds;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    if (lastSyncedAt != null) {
      $result.lastSyncedAt = lastSyncedAt;
    }
    if (eventCount != null) {
      $result.eventCount = eventCount;
    }
    if (occasionCount != null) {
      $result.occasionCount = occasionCount;
    }
    if (icsSubscriptionUrl != null) {
      $result.icsSubscriptionUrl = icsSubscriptionUrl;
    }
    if (postCount != null) {
      $result.postCount = postCount;
    }
    if (rssSubscriptionUrl != null) {
      $result.rssSubscriptionUrl = rssSubscriptionUrl;
    }
    if (atomSubscriptionUrl != null) {
      $result.atomSubscriptionUrl = atomSubscriptionUrl;
    }
    return $result;
  }
  SyncSource._() : super();
  factory SyncSource.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SyncSource.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, SyncSource_Configuration> _SyncSource_ConfigurationByTag = {
    9 : SyncSource_Configuration.icsSubscriptionUrl,
    11 : SyncSource_Configuration.rssSubscriptionUrl,
    12 : SyncSource_Configuration.atomSubscriptionUrl,
    0 : SyncSource_Configuration.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SyncSource', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [9, 11, 12])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'owner', subBuilder: $5.Author.create)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'syncIntervalSeconds', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(5, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(6, _omitFieldNames ? '' : 'lastSyncedAt', subBuilder: $13.Timestamp.create)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'eventCount', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'occasionCount', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(9, _omitFieldNames ? '' : 'icsSubscriptionUrl')
    ..a<$fixnum.Int64>(10, _omitFieldNames ? '' : 'postCount', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(11, _omitFieldNames ? '' : 'rssSubscriptionUrl')
    ..aOS(12, _omitFieldNames ? '' : 'atomSubscriptionUrl')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SyncSource clone() => SyncSource()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SyncSource copyWith(void Function(SyncSource) updates) => super.copyWith((message) => updates(message as SyncSource)) as SyncSource;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncSource create() => SyncSource._();
  SyncSource createEmptyInstance() => create();
  static $pb.PbList<SyncSource> createRepeated() => $pb.PbList<SyncSource>();
  @$core.pragma('dart2js:noInline')
  static SyncSource getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncSource>(create);
  static SyncSource? _defaultInstance;

  SyncSource_Configuration whichConfiguration() => _SyncSource_ConfigurationByTag[$_whichOneof(0)]!;
  void clearConfiguration() => clearField($_whichOneof(0));

  /// Unique ID for the synchronization.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The user information for the owner of this sync source.
  @$pb.TagNumber(2)
  $5.Author get owner => $_getN(1);
  @$pb.TagNumber(2)
  set owner($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwner() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwner() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureOwner() => $_ensure(1);

  /// How frequently the sync should happen in seconds.
  @$pb.TagNumber(3)
  $fixnum.Int64 get syncIntervalSeconds => $_getI64(2);
  @$pb.TagNumber(3)
  set syncIntervalSeconds($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSyncIntervalSeconds() => $_has(2);
  @$pb.TagNumber(3)
  void clearSyncIntervalSeconds() => clearField(3);

  /// The time the SyncSource was created.
  @$pb.TagNumber(4)
  $13.Timestamp get createdAt => $_getN(3);
  @$pb.TagNumber(4)
  set createdAt($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatedAt() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureCreatedAt() => $_ensure(3);

  /// The time the SyncSource was last updated.
  @$pb.TagNumber(5)
  $13.Timestamp get updatedAt => $_getN(4);
  @$pb.TagNumber(5)
  set updatedAt($13.Timestamp v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasUpdatedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearUpdatedAt() => clearField(5);
  @$pb.TagNumber(5)
  $13.Timestamp ensureUpdatedAt() => $_ensure(4);

  /// The time the SyncSource was last synced.
  @$pb.TagNumber(6)
  $13.Timestamp get lastSyncedAt => $_getN(5);
  @$pb.TagNumber(6)
  set lastSyncedAt($13.Timestamp v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasLastSyncedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastSyncedAt() => clearField(6);
  @$pb.TagNumber(6)
  $13.Timestamp ensureLastSyncedAt() => $_ensure(5);

  /// The number of events total associated with this SyncSource. Recomputed
  /// on each sync.
  @$pb.TagNumber(7)
  $fixnum.Int64 get eventCount => $_getI64(6);
  @$pb.TagNumber(7)
  set eventCount($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEventCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearEventCount() => clearField(7);

  /// The number of occasions total associated with this SyncSource. Recomputed
  /// on each sync.
  @$pb.TagNumber(8)
  $fixnum.Int64 get occasionCount => $_getI64(7);
  @$pb.TagNumber(8)
  set occasionCount($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasOccasionCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearOccasionCount() => clearField(8);

  /// The iCal subscription URL for the calendar sync. Creates/updates Events/Occasions.
  @$pb.TagNumber(9)
  $core.String get icsSubscriptionUrl => $_getSZ(8);
  @$pb.TagNumber(9)
  set icsSubscriptionUrl($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIcsSubscriptionUrl() => $_has(8);
  @$pb.TagNumber(9)
  void clearIcsSubscriptionUrl() => clearField(9);

  /// The number of posts total associated with this SyncSource. Populated for an RSS/Atom
  /// source (recomputed on each sync, like `event_count`/`occasion_count` are for an
  /// ICS source); always 0 for an ICS source, which syncs Events/Occasions instead.
  @$pb.TagNumber(10)
  $fixnum.Int64 get postCount => $_getI64(9);
  @$pb.TagNumber(10)
  set postCount($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasPostCount() => $_has(9);
  @$pb.TagNumber(10)
  void clearPostCount() => clearField(10);

  /// The RSS subscription URL for the feed sync. Creates/updates plain Posts.
  @$pb.TagNumber(11)
  $core.String get rssSubscriptionUrl => $_getSZ(10);
  @$pb.TagNumber(11)
  set rssSubscriptionUrl($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasRssSubscriptionUrl() => $_has(10);
  @$pb.TagNumber(11)
  void clearRssSubscriptionUrl() => clearField(11);

  /// The Atom subscription URL for the feed sync. Creates/updates plain Posts.
  @$pb.TagNumber(12)
  $core.String get atomSubscriptionUrl => $_getSZ(11);
  @$pb.TagNumber(12)
  set atomSubscriptionUrl($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasAtomSubscriptionUrl() => $_has(11);
  @$pb.TagNumber(12)
  void clearAtomSubscriptionUrl() => clearField(12);
}

class GetSyncSourcesResponse extends $pb.GeneratedMessage {
  factory GetSyncSourcesResponse({
    $core.Iterable<SyncSource>? sources,
  }) {
    final $result = create();
    if (sources != null) {
      $result.sources.addAll(sources);
    }
    return $result;
  }
  GetSyncSourcesResponse._() : super();
  factory GetSyncSourcesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetSyncSourcesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetSyncSourcesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<SyncSource>(1, _omitFieldNames ? '' : 'sources', $pb.PbFieldType.PM, subBuilder: SyncSource.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetSyncSourcesResponse clone() => GetSyncSourcesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetSyncSourcesResponse copyWith(void Function(GetSyncSourcesResponse) updates) => super.copyWith((message) => updates(message as GetSyncSourcesResponse)) as GetSyncSourcesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSyncSourcesResponse create() => GetSyncSourcesResponse._();
  GetSyncSourcesResponse createEmptyInstance() => create();
  static $pb.PbList<GetSyncSourcesResponse> createRepeated() => $pb.PbList<GetSyncSourcesResponse>();
  @$core.pragma('dart2js:noInline')
  static GetSyncSourcesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetSyncSourcesResponse>(create);
  static GetSyncSourcesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<SyncSource> get sources => $_getList(0);
}

/// Request to delete a SyncSource.
class DeleteSyncSourceRequest extends $pb.GeneratedMessage {
  factory DeleteSyncSourceRequest({
    SyncSource? source,
    $core.bool? deleteSyncedEvents,
  }) {
    final $result = create();
    if (source != null) {
      $result.source = source;
    }
    if (deleteSyncedEvents != null) {
      $result.deleteSyncedEvents = deleteSyncedEvents;
    }
    return $result;
  }
  DeleteSyncSourceRequest._() : super();
  factory DeleteSyncSourceRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeleteSyncSourceRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeleteSyncSourceRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<SyncSource>(1, _omitFieldNames ? '' : 'source', subBuilder: SyncSource.create)
    ..aOB(2, _omitFieldNames ? '' : 'deleteSyncedEvents')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeleteSyncSourceRequest clone() => DeleteSyncSourceRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeleteSyncSourceRequest copyWith(void Function(DeleteSyncSourceRequest) updates) => super.copyWith((message) => updates(message as DeleteSyncSourceRequest)) as DeleteSyncSourceRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteSyncSourceRequest create() => DeleteSyncSourceRequest._();
  DeleteSyncSourceRequest createEmptyInstance() => create();
  static $pb.PbList<DeleteSyncSourceRequest> createRepeated() => $pb.PbList<DeleteSyncSourceRequest>();
  @$core.pragma('dart2js:noInline')
  static DeleteSyncSourceRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteSyncSourceRequest>(create);
  static DeleteSyncSourceRequest? _defaultInstance;

  /// The source to be deleted.
  @$pb.TagNumber(1)
  SyncSource get source => $_getN(0);
  @$pb.TagNumber(1)
  set source(SyncSource v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => clearField(1);
  @$pb.TagNumber(1)
  SyncSource ensureSource() => $_ensure(0);

  /// Whether to delete synced events.
  @$pb.TagNumber(2)
  $core.bool get deleteSyncedEvents => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteSyncedEvents($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeleteSyncedEvents() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteSyncedEvents() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
