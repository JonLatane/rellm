//
//  Generated code. Do not modify.
//  source: users.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'ai_providers.pb.dart' as $11;
import 'federation.pb.dart' as $1;
import 'google/protobuf/timestamp.pb.dart' as $13;
import 'market.pb.dart' as $12;
import 'media.pb.dart' as $5;
import 'permissions.pbenum.dart' as $15;
import 'sync.pb.dart' as $10;
import 'users.pbenum.dart';
import 'visibility_moderation.pbenum.dart' as $14;

export 'users.pbenum.dart';

/// Model for a Rellm user. This user may have [`Media`](#rellm-Media), [`Group`](#rellm-Group) [`Membership`](#rellm-Membership)s,
/// [`Post`](#rellm-Post)s, [`Event`](#rellm-Event)s, and other objects associated with them.
class User extends $pb.GeneratedMessage {
  factory User({
    $core.String? id,
    $core.String? username,
    $core.String? realName,
    ContactMethod? email,
    ContactMethod? phone,
    $core.Iterable<$15.Permission>? permissions,
    $5.MediaReference? avatar,
    $core.String? bio,
    $fixnum.Int64? mediaStorageLimitBytes,
    $fixnum.Int64? mediaStorageBytesUsed,
    $14.Visibility? visibility,
    $14.Moderation? moderation,
    $14.Moderation? defaultFollowModeration,
    $core.int? followerCount,
    $core.int? followingCount,
    $core.int? friendCount,
    $core.int? groupCount,
    $core.int? postCount,
    $core.int? responseCount,
    $core.int? eventCount,
    $core.int? occasionCount,
    Follow? currentUserFollow,
    Follow? targetCurrentUserFollow,
    Membership? currentGroupMembership,
    $core.Iterable<$1.FederatedAccount>? federatedProfiles,
    $core.Iterable<$10.SyncDestination>? syncDestinations,
    $core.Iterable<$10.SyncSource>? syncSources,
    $core.Iterable<$11.AIModel>? aiModels,
    $core.Iterable<$12.MarketSubscription>? marketSubscriptions,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (username != null) {
      $result.username = username;
    }
    if (realName != null) {
      $result.realName = realName;
    }
    if (email != null) {
      $result.email = email;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    if (avatar != null) {
      $result.avatar = avatar;
    }
    if (bio != null) {
      $result.bio = bio;
    }
    if (mediaStorageLimitBytes != null) {
      $result.mediaStorageLimitBytes = mediaStorageLimitBytes;
    }
    if (mediaStorageBytesUsed != null) {
      $result.mediaStorageBytesUsed = mediaStorageBytesUsed;
    }
    if (visibility != null) {
      $result.visibility = visibility;
    }
    if (moderation != null) {
      $result.moderation = moderation;
    }
    if (defaultFollowModeration != null) {
      $result.defaultFollowModeration = defaultFollowModeration;
    }
    if (followerCount != null) {
      $result.followerCount = followerCount;
    }
    if (followingCount != null) {
      $result.followingCount = followingCount;
    }
    if (friendCount != null) {
      $result.friendCount = friendCount;
    }
    if (groupCount != null) {
      $result.groupCount = groupCount;
    }
    if (postCount != null) {
      $result.postCount = postCount;
    }
    if (responseCount != null) {
      $result.responseCount = responseCount;
    }
    if (eventCount != null) {
      $result.eventCount = eventCount;
    }
    if (occasionCount != null) {
      $result.occasionCount = occasionCount;
    }
    if (currentUserFollow != null) {
      $result.currentUserFollow = currentUserFollow;
    }
    if (targetCurrentUserFollow != null) {
      $result.targetCurrentUserFollow = targetCurrentUserFollow;
    }
    if (currentGroupMembership != null) {
      $result.currentGroupMembership = currentGroupMembership;
    }
    if (federatedProfiles != null) {
      $result.federatedProfiles.addAll(federatedProfiles);
    }
    if (syncDestinations != null) {
      $result.syncDestinations.addAll(syncDestinations);
    }
    if (syncSources != null) {
      $result.syncSources.addAll(syncSources);
    }
    if (aiModels != null) {
      $result.aiModels.addAll(aiModels);
    }
    if (marketSubscriptions != null) {
      $result.marketSubscriptions.addAll(marketSubscriptions);
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  User._() : super();
  factory User.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory User.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'User', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'realName')
    ..aOM<ContactMethod>(4, _omitFieldNames ? '' : 'email', subBuilder: ContactMethod.create)
    ..aOM<ContactMethod>(5, _omitFieldNames ? '' : 'phone', subBuilder: ContactMethod.create)
    ..pc<$15.Permission>(6, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..aOM<$5.MediaReference>(7, _omitFieldNames ? '' : 'avatar', subBuilder: $5.MediaReference.create)
    ..aOS(8, _omitFieldNames ? '' : 'bio')
    ..a<$fixnum.Int64>(10, _omitFieldNames ? '' : 'mediaStorageLimitBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(11, _omitFieldNames ? '' : 'mediaStorageBytesUsed', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<$14.Visibility>(20, _omitFieldNames ? '' : 'visibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..e<$14.Moderation>(21, _omitFieldNames ? '' : 'moderation', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Moderation>(30, _omitFieldNames ? '' : 'defaultFollowModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..a<$core.int>(31, _omitFieldNames ? '' : 'followerCount', $pb.PbFieldType.O3)
    ..a<$core.int>(32, _omitFieldNames ? '' : 'followingCount', $pb.PbFieldType.O3)
    ..a<$core.int>(33, _omitFieldNames ? '' : 'friendCount', $pb.PbFieldType.O3)
    ..a<$core.int>(34, _omitFieldNames ? '' : 'groupCount', $pb.PbFieldType.O3)
    ..a<$core.int>(35, _omitFieldNames ? '' : 'postCount', $pb.PbFieldType.O3)
    ..a<$core.int>(36, _omitFieldNames ? '' : 'responseCount', $pb.PbFieldType.O3)
    ..a<$core.int>(37, _omitFieldNames ? '' : 'eventCount', $pb.PbFieldType.O3)
    ..a<$core.int>(38, _omitFieldNames ? '' : 'occasionCount', $pb.PbFieldType.O3)
    ..aOM<Follow>(50, _omitFieldNames ? '' : 'currentUserFollow', subBuilder: Follow.create)
    ..aOM<Follow>(51, _omitFieldNames ? '' : 'targetCurrentUserFollow', subBuilder: Follow.create)
    ..aOM<Membership>(52, _omitFieldNames ? '' : 'currentGroupMembership', subBuilder: Membership.create)
    ..pc<$1.FederatedAccount>(81, _omitFieldNames ? '' : 'federatedProfiles', $pb.PbFieldType.PM, subBuilder: $1.FederatedAccount.create)
    ..pc<$10.SyncDestination>(82, _omitFieldNames ? '' : 'syncDestinations', $pb.PbFieldType.PM, subBuilder: $10.SyncDestination.create)
    ..pc<$10.SyncSource>(83, _omitFieldNames ? '' : 'syncSources', $pb.PbFieldType.PM, subBuilder: $10.SyncSource.create)
    ..pc<$11.AIModel>(84, _omitFieldNames ? '' : 'aiModels', $pb.PbFieldType.PM, subBuilder: $11.AIModel.create)
    ..pc<$12.MarketSubscription>(85, _omitFieldNames ? '' : 'marketSubscriptions', $pb.PbFieldType.PM, subBuilder: $12.MarketSubscription.create)
    ..aOM<$13.Timestamp>(100, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(101, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  User clone() => User()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  User copyWith(void Function(User) updates) => super.copyWith((message) => updates(message as User)) as User;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static User create() => User._();
  User createEmptyInstance() => create();
  static $pb.PbList<User> createRepeated() => $pb.PbList<User>();
  @$core.pragma('dart2js:noInline')
  static User getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<User>(create);
  static User? _defaultInstance;

  /// Permanent string ID for the user. Will never contain a `@` symbol.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Impermanent string username for the user. Will never contain a `@` symbol.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// The user's real name.
  @$pb.TagNumber(3)
  $core.String get realName => $_getSZ(2);
  @$pb.TagNumber(3)
  set realName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRealName() => $_has(2);
  @$pb.TagNumber(3)
  void clearRealName() => clearField(3);

  /// The user's email address.
  @$pb.TagNumber(4)
  ContactMethod get email => $_getN(3);
  @$pb.TagNumber(4)
  set email(ContactMethod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmail() => clearField(4);
  @$pb.TagNumber(4)
  ContactMethod ensureEmail() => $_ensure(3);

  /// The user's phone number.
  @$pb.TagNumber(5)
  ContactMethod get phone => $_getN(4);
  @$pb.TagNumber(5)
  set phone(ContactMethod v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasPhone() => $_has(4);
  @$pb.TagNumber(5)
  void clearPhone() => clearField(5);
  @$pb.TagNumber(5)
  ContactMethod ensurePhone() => $_ensure(4);

  /// The user's permissions. See [`Permission`](#rellm-Permission) for details.
  @$pb.TagNumber(6)
  $core.List<$15.Permission> get permissions => $_getList(5);

  /// The user's avatar. Note that its visibility is managed by the User and thus
  /// it may not be accessible to the current user.
  @$pb.TagNumber(7)
  $5.MediaReference get avatar => $_getN(6);
  @$pb.TagNumber(7)
  set avatar($5.MediaReference v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAvatar() => $_has(6);
  @$pb.TagNumber(7)
  void clearAvatar() => clearField(7);
  @$pb.TagNumber(7)
  $5.MediaReference ensureAvatar() => $_ensure(6);

  /// The user's bio.
  @$pb.TagNumber(8)
  $core.String get bio => $_getSZ(7);
  @$pb.TagNumber(8)
  set bio($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasBio() => $_has(7);
  @$pb.TagNumber(8)
  void clearBio() => clearField(8);

  /// The maximum number of bytes this user's Media (see `Media.sizes[].size_bytes`) may
  /// collectively occupy in storage. Enforced by `POST /media` (see `Media`'s own doc), which
  /// rejects an upload that would push `media_storage_bytes_used` over this limit with an HTTP 413
  /// and a plaintext error body. Unset means unlimited.
  @$pb.TagNumber(10)
  $fixnum.Int64 get mediaStorageLimitBytes => $_getI64(8);
  @$pb.TagNumber(10)
  set mediaStorageLimitBytes($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(10)
  $core.bool hasMediaStorageLimitBytes() => $_has(8);
  @$pb.TagNumber(10)
  void clearMediaStorageLimitBytes() => clearField(10);

  /// The total size, in bytes, of every stored copy (original plus any converted sizes) of every
  /// Media item this user owns -- the sum of `Media.sizes[].size_bytes` across all their Media.
  /// A denormalized counter, recomputed (never trusted from client input) after every operation
  /// that could change it -- upload, delete, size conversion, `DeleteMediaSizes` -- by
  /// `backend/src/logic/user_counts.rs`'s `update_media_storage_used`, and self-healed on an
  /// interval by `bin/update_user_counts.rs` the same way every other denormalized `User` counter
  /// (`follower_count`, `post_count`, etc.) is.
  @$pb.TagNumber(11)
  $fixnum.Int64 get mediaStorageBytesUsed => $_getI64(9);
  @$pb.TagNumber(11)
  set mediaStorageBytesUsed($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(11)
  $core.bool hasMediaStorageBytesUsed() => $_has(9);
  @$pb.TagNumber(11)
  void clearMediaStorageBytesUsed() => clearField(11);

  /// User visibility is a bit different from Post visibility.
  /// LIMITED means the user can only be seen by users they follow
  /// (as opposed to Posts' individualized visibilities).
  /// PRIVATE visibility means no one can see the user.
  /// See server_configuration.proto for details about PRIVATE
  /// users' ability to creep.
  @$pb.TagNumber(20)
  $14.Visibility get visibility => $_getN(10);
  @$pb.TagNumber(20)
  set visibility($14.Visibility v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasVisibility() => $_has(10);
  @$pb.TagNumber(20)
  void clearVisibility() => clearField(20);

  /// The user's moderation status. See [`Moderation`](#rellm-Moderation) for details.
  @$pb.TagNumber(21)
  $14.Moderation get moderation => $_getN(11);
  @$pb.TagNumber(21)
  set moderation($14.Moderation v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasModeration() => $_has(11);
  @$pb.TagNumber(21)
  void clearModeration() => clearField(21);

  /// Only PENDING or UNMODERATED are valid.
  @$pb.TagNumber(30)
  $14.Moderation get defaultFollowModeration => $_getN(12);
  @$pb.TagNumber(30)
  set defaultFollowModeration($14.Moderation v) { setField(30, v); }
  @$pb.TagNumber(30)
  $core.bool hasDefaultFollowModeration() => $_has(12);
  @$pb.TagNumber(30)
  void clearDefaultFollowModeration() => clearField(30);

  /// The number of users following this user.
  @$pb.TagNumber(31)
  $core.int get followerCount => $_getIZ(13);
  @$pb.TagNumber(31)
  set followerCount($core.int v) { $_setSignedInt32(13, v); }
  @$pb.TagNumber(31)
  $core.bool hasFollowerCount() => $_has(13);
  @$pb.TagNumber(31)
  void clearFollowerCount() => clearField(31);

  /// The number of users this user is following.
  @$pb.TagNumber(32)
  $core.int get followingCount => $_getIZ(14);
  @$pb.TagNumber(32)
  set followingCount($core.int v) { $_setSignedInt32(14, v); }
  @$pb.TagNumber(32)
  $core.bool hasFollowingCount() => $_has(14);
  @$pb.TagNumber(32)
  void clearFollowingCount() => clearField(32);

  /// The number of users this user mutually follows (and is followed by).
  @$pb.TagNumber(33)
  $core.int get friendCount => $_getIZ(15);
  @$pb.TagNumber(33)
  set friendCount($core.int v) { $_setSignedInt32(15, v); }
  @$pb.TagNumber(33)
  $core.bool hasFriendCount() => $_has(15);
  @$pb.TagNumber(33)
  void clearFriendCount() => clearField(33);

  /// The number of groups this user is a member of.
  @$pb.TagNumber(34)
  $core.int get groupCount => $_getIZ(16);
  @$pb.TagNumber(34)
  set groupCount($core.int v) { $_setSignedInt32(16, v); }
  @$pb.TagNumber(34)
  $core.bool hasGroupCount() => $_has(16);
  @$pb.TagNumber(34)
  void clearGroupCount() => clearField(34);

  /// The number of posts this user has made.
  @$pb.TagNumber(35)
  $core.int get postCount => $_getIZ(17);
  @$pb.TagNumber(35)
  set postCount($core.int v) { $_setSignedInt32(17, v); }
  @$pb.TagNumber(35)
  $core.bool hasPostCount() => $_has(17);
  @$pb.TagNumber(35)
  void clearPostCount() => clearField(35);

  /// The number of responses to [`Post`](#rellm-Post)s and [`Event`](#rellm-Event)s this user has made.
  @$pb.TagNumber(36)
  $core.int get responseCount => $_getIZ(18);
  @$pb.TagNumber(36)
  set responseCount($core.int v) { $_setSignedInt32(18, v); }
  @$pb.TagNumber(36)
  $core.bool hasResponseCount() => $_has(18);
  @$pb.TagNumber(36)
  void clearResponseCount() => clearField(36);

  /// The number of events this user has created.
  @$pb.TagNumber(37)
  $core.int get eventCount => $_getIZ(19);
  @$pb.TagNumber(37)
  set eventCount($core.int v) { $_setSignedInt32(19, v); }
  @$pb.TagNumber(37)
  $core.bool hasEventCount() => $_has(19);
  @$pb.TagNumber(37)
  void clearEventCount() => clearField(37);

  /// The number of occasions this user has created (across all of their events).
  @$pb.TagNumber(38)
  $core.int get occasionCount => $_getIZ(20);
  @$pb.TagNumber(38)
  set occasionCount($core.int v) { $_setSignedInt32(20, v); }
  @$pb.TagNumber(38)
  $core.bool hasOccasionCount() => $_has(20);
  @$pb.TagNumber(38)
  void clearOccasionCount() => clearField(38);

  /// Presence indicates the current user is following
  /// or has a pending follow request for this user.
  @$pb.TagNumber(50)
  Follow get currentUserFollow => $_getN(21);
  @$pb.TagNumber(50)
  set currentUserFollow(Follow v) { setField(50, v); }
  @$pb.TagNumber(50)
  $core.bool hasCurrentUserFollow() => $_has(21);
  @$pb.TagNumber(50)
  void clearCurrentUserFollow() => clearField(50);
  @$pb.TagNumber(50)
  Follow ensureCurrentUserFollow() => $_ensure(21);

  /// Presence indicates this user is following or has
  /// a pending follow request for the current user.
  @$pb.TagNumber(51)
  Follow get targetCurrentUserFollow => $_getN(22);
  @$pb.TagNumber(51)
  set targetCurrentUserFollow(Follow v) { setField(51, v); }
  @$pb.TagNumber(51)
  $core.bool hasTargetCurrentUserFollow() => $_has(22);
  @$pb.TagNumber(51)
  void clearTargetCurrentUserFollow() => clearField(51);
  @$pb.TagNumber(51)
  Follow ensureTargetCurrentUserFollow() => $_ensure(22);

  /// Returned by [`GetMembers`](#grpc-api-GetMembers) calls, for use when managing [`Group`](#rellm-Group) [`Membership`](#rellm-Membership)s.
  /// The [`Membership`](#rellm-Membership) should match the [`Group`](#rellm-Group) from the originating [`GetMembersRequest`](#rellm-GetMembersRequest),
  /// providing whether the user is a member of that [`Group`](#rellm-Group), has been invited, requested to join, etc..
  @$pb.TagNumber(52)
  Membership get currentGroupMembership => $_getN(23);
  @$pb.TagNumber(52)
  set currentGroupMembership(Membership v) { setField(52, v); }
  @$pb.TagNumber(52)
  $core.bool hasCurrentGroupMembership() => $_has(23);
  @$pb.TagNumber(52)
  void clearCurrentGroupMembership() => clearField(52);
  @$pb.TagNumber(52)
  Membership ensureCurrentGroupMembership() => $_ensure(23);

  /// Federated profiles for the user. *Not always loaded.* This is a list of profiles from other servers
  /// that the user has connected to their account. Managed by the user via
  /// `Federate`
  @$pb.TagNumber(81)
  $core.List<$1.FederatedAccount> get federatedProfiles => $_getList(24);

  /// The target user's own linked SyncDestinations (e.g. Facebook Pages).
  /// Populated by [`GetUsers`](#grpc-api-GetUsers)' single-user lookups (by username or by user_id) when the
  /// viewer is the target user themselves (and holds `SYNC_EVENTS_TO_FACEBOOK` or
  /// `SYNC_POSTS_TO_FACEBOOK`) or an Admin, and by [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser)
  /// (always a self-view) - always empty otherwise, including via every other [`GetUsers`](#grpc-api-GetUsers)
  /// listing type.
  @$pb.TagNumber(82)
  $core.List<$10.SyncDestination> get syncDestinations => $_getList(25);

  /// The target user's own [`SyncSource`](#rellm-SyncSource)s. Unlike `sync_destinations`, also populated for
  /// the target user themselves *or an Admin* across every [`GetUsers`](#grpc-api-GetUsers) listing type (not just
  /// single-user lookups) - e.g. an Admin's `EVERYONE` listing gets every returned user's sources
  /// filled in, batch-loaded in one query rather than per-user. Also populated by
  /// [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser) (always a self-view). Always empty for
  /// any other viewer.
  @$pb.TagNumber(83)
  $core.List<$10.SyncSource> get syncSources => $_getList(26);

  /// Every [`AIProvider`](#rellm-AIProvider) model the target user may currently call - their own
  /// providers' models, plus any models granted to them on other users' providers (see
  /// [`AIModel`](#rellm-AIModel)). Gated and populated the same way as `sync_sources`
  /// (target user themselves, or an Admin, across any [`GetUsers`](#grpc-api-GetUsers) listing type, plus
  /// [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser)).
  @$pb.TagNumber(84)
  $core.List<$11.AIModel> get aiModels => $_getList(27);

  /// The target user's own MarketSubscriptions (`market.proto`), each with its own
  /// `billing_history`. Gated and populated the same way as `ai_models`/`sync_sources` (target user
  /// themselves, or an Admin, across any [`GetUsers`](#grpc-api-GetUsers) listing type, plus
  /// [`Login`](#grpc-api-Login)/[`CreateAccount`](#grpc-api-CreateAccount)/[`GetCurrentUser`](#grpc-api-GetCurrentUser)).
  @$pb.TagNumber(85)
  $core.List<$12.MarketSubscription> get marketSubscriptions => $_getList(28);

  /// The time the user was created.
  @$pb.TagNumber(100)
  $13.Timestamp get createdAt => $_getN(29);
  @$pb.TagNumber(100)
  set createdAt($13.Timestamp v) { setField(100, v); }
  @$pb.TagNumber(100)
  $core.bool hasCreatedAt() => $_has(29);
  @$pb.TagNumber(100)
  void clearCreatedAt() => clearField(100);
  @$pb.TagNumber(100)
  $13.Timestamp ensureCreatedAt() => $_ensure(29);

  /// The time the user was last updated.
  @$pb.TagNumber(101)
  $13.Timestamp get updatedAt => $_getN(30);
  @$pb.TagNumber(101)
  set updatedAt($13.Timestamp v) { setField(101, v); }
  @$pb.TagNumber(101)
  $core.bool hasUpdatedAt() => $_has(30);
  @$pb.TagNumber(101)
  void clearUpdatedAt() => clearField(101);
  @$pb.TagNumber(101)
  $13.Timestamp ensureUpdatedAt() => $_ensure(30);
}

/// Model for a user's follow of another user.
class Follow extends $pb.GeneratedMessage {
  factory Follow({
    $core.String? userId,
    $core.String? targetUserId,
    $14.Moderation? targetUserModeration,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (targetUserId != null) {
      $result.targetUserId = targetUserId;
    }
    if (targetUserModeration != null) {
      $result.targetUserModeration = targetUserModeration;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  Follow._() : super();
  factory Follow.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Follow.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Follow', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'targetUserId')
    ..e<$14.Moderation>(3, _omitFieldNames ? '' : 'targetUserModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(5, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Follow clone() => Follow()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Follow copyWith(void Function(Follow) updates) => super.copyWith((message) => updates(message as Follow)) as Follow;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Follow create() => Follow._();
  Follow createEmptyInstance() => create();
  static $pb.PbList<Follow> createRepeated() => $pb.PbList<Follow>();
  @$core.pragma('dart2js:noInline')
  static Follow getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Follow>(create);
  static Follow? _defaultInstance;

  /// The follower in the relationship.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The user being followed.
  @$pb.TagNumber(2)
  $core.String get targetUserId => $_getSZ(1);
  @$pb.TagNumber(2)
  set targetUserId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTargetUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTargetUserId() => clearField(2);

  /// Tracks whether the target user needs to approve the follow.
  @$pb.TagNumber(3)
  $14.Moderation get targetUserModeration => $_getN(2);
  @$pb.TagNumber(3)
  set targetUserModeration($14.Moderation v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasTargetUserModeration() => $_has(2);
  @$pb.TagNumber(3)
  void clearTargetUserModeration() => clearField(3);

  /// The time the follow was created.
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

  /// The time the follow was last updated.
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
}

/// Model for a user's membership in a group. Memberships are generically
/// included as part of User models when relevant in Rellm, but UIs should use the group_id
/// to reconcile memberships with groups.
class Membership extends $pb.GeneratedMessage {
  factory Membership({
    $core.String? userId,
    $core.String? groupId,
    $core.Iterable<$15.Permission>? permissions,
    $14.Moderation? groupModeration,
    $14.Moderation? userModeration,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    if (groupModeration != null) {
      $result.groupModeration = groupModeration;
    }
    if (userModeration != null) {
      $result.userModeration = userModeration;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  Membership._() : super();
  factory Membership.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Membership.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Membership', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'groupId')
    ..pc<$15.Permission>(3, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..e<$14.Moderation>(4, _omitFieldNames ? '' : 'groupModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..e<$14.Moderation>(5, _omitFieldNames ? '' : 'userModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..aOM<$13.Timestamp>(6, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(7, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Membership clone() => Membership()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Membership copyWith(void Function(Membership) updates) => super.copyWith((message) => updates(message as Membership)) as Membership;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Membership create() => Membership._();
  Membership createEmptyInstance() => create();
  static $pb.PbList<Membership> createRepeated() => $pb.PbList<Membership>();
  @$core.pragma('dart2js:noInline')
  static Membership getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Membership>(create);
  static Membership? _defaultInstance;

  /// The member (or requested/invited member).
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The group the membership pertains to.
  @$pb.TagNumber(2)
  $core.String get groupId => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasGroupId() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupId() => clearField(2);

  /// Valid Membership Permissions are:  `VIEW_POSTS`, `CREATE_POSTS`, `MODERATE_POSTS`, `VIEW_EVENTS`, CREATE_EVENTS, `MODERATE_EVENTS`, `ADMIN`, `RUN_BOTS`, and `MODERATE_USERS`
  @$pb.TagNumber(3)
  $core.List<$15.Permission> get permissions => $_getList(2);

  /// Tracks whether group moderators need to approve the membership.
  @$pb.TagNumber(4)
  $14.Moderation get groupModeration => $_getN(3);
  @$pb.TagNumber(4)
  set groupModeration($14.Moderation v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasGroupModeration() => $_has(3);
  @$pb.TagNumber(4)
  void clearGroupModeration() => clearField(4);

  /// Tracks whether the user needs to approve the membership.
  @$pb.TagNumber(5)
  $14.Moderation get userModeration => $_getN(4);
  @$pb.TagNumber(5)
  set userModeration($14.Moderation v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserModeration() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserModeration() => clearField(5);

  /// The time the membership was created.
  @$pb.TagNumber(6)
  $13.Timestamp get createdAt => $_getN(5);
  @$pb.TagNumber(6)
  set createdAt($13.Timestamp v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasCreatedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAt() => clearField(6);
  @$pb.TagNumber(6)
  $13.Timestamp ensureCreatedAt() => $_ensure(5);

  /// The time the membership was last updated.
  @$pb.TagNumber(7)
  $13.Timestamp get updatedAt => $_getN(6);
  @$pb.TagNumber(7)
  set updatedAt($13.Timestamp v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasUpdatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearUpdatedAt() => clearField(7);
  @$pb.TagNumber(7)
  $13.Timestamp ensureUpdatedAt() => $_ensure(6);
}

/// A contact method for a user (`tel:` or `mailto:`). SMS verification via
/// [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification)/
/// [`VerifyContactMethod`](#grpc-api-VerifyContactMethod), backed by whichever of
/// [`TwilioConfig`](#rellm-TwilioConfig)/[`BirdConfig`](#rellm-BirdConfig)/
/// [`TelnyxConfig`](#rellm-TelnyxConfig) the server has enabled -- see `supported_by_server` below,
/// and [`ContactProtocol`](#rellm-ContactProtocol) for the corresponding server-wide toggle.
/// `mailto:` has no verification provider yet.
class ContactMethod extends $pb.GeneratedMessage {
  factory ContactMethod({
    $core.String? value,
    $14.Visibility? visibility,
    $core.bool? supportedByServer,
    $13.Timestamp? verifiedAt,
    ContactMethodVerification? verificationInProgress,
    ContactConsentState? consentState,
    $core.Iterable<ContactConsentChange>? consentHistory,
  }) {
    final $result = create();
    if (value != null) {
      $result.value = value;
    }
    if (visibility != null) {
      $result.visibility = visibility;
    }
    if (supportedByServer != null) {
      $result.supportedByServer = supportedByServer;
    }
    if (verifiedAt != null) {
      $result.verifiedAt = verifiedAt;
    }
    if (verificationInProgress != null) {
      $result.verificationInProgress = verificationInProgress;
    }
    if (consentState != null) {
      $result.consentState = consentState;
    }
    if (consentHistory != null) {
      $result.consentHistory.addAll(consentHistory);
    }
    return $result;
  }
  ContactMethod._() : super();
  factory ContactMethod.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactMethod.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactMethod', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..e<$14.Visibility>(2, _omitFieldNames ? '' : 'visibility', $pb.PbFieldType.OE, defaultOrMaker: $14.Visibility.VISIBILITY_UNKNOWN, valueOf: $14.Visibility.valueOf, enumValues: $14.Visibility.values)
    ..aOB(3, _omitFieldNames ? '' : 'supportedByServer')
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'verifiedAt', subBuilder: $13.Timestamp.create)
    ..aOM<ContactMethodVerification>(5, _omitFieldNames ? '' : 'verificationInProgress', subBuilder: ContactMethodVerification.create)
    ..e<ContactConsentState>(6, _omitFieldNames ? '' : 'consentState', $pb.PbFieldType.OE, defaultOrMaker: ContactConsentState.CONTACT_CONSENT_REVOKED, valueOf: ContactConsentState.valueOf, enumValues: ContactConsentState.values)
    ..pc<ContactConsentChange>(7, _omitFieldNames ? '' : 'consentHistory', $pb.PbFieldType.PM, subBuilder: ContactConsentChange.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactMethod clone() => ContactMethod()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactMethod copyWith(void Function(ContactMethod) updates) => super.copyWith((message) => updates(message as ContactMethod)) as ContactMethod;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactMethod create() => ContactMethod._();
  ContactMethod createEmptyInstance() => create();
  static $pb.PbList<ContactMethod> createRepeated() => $pb.PbList<ContactMethod>();
  @$core.pragma('dart2js:noInline')
  static ContactMethod getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactMethod>(create);
  static ContactMethod? _defaultInstance;

  /// Either a valid `mailto:` or valid `tel:` URL.
  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => clearField(1);

  /// The visibility of the contact method.
  @$pb.TagNumber(2)
  $14.Visibility get visibility => $_getN(1);
  @$pb.TagNumber(2)
  set visibility($14.Visibility v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasVisibility() => $_has(1);
  @$pb.TagNumber(2)
  void clearVisibility() => clearField(2);

  /// Server-side flag indicating whether the server can verify (and otherwise interact via) the
  /// contact method. Always computed server-side (never trusted from client input) -- `true` iff
  /// this value's scheme (`tel:`/`mailto:`) is the corresponding
  /// [`ContactProtocol`](#rellm-ContactProtocol) currently listed in
  /// `ServerConfiguration.supported_contact_protocols` (see the
  /// [`ServerConfiguration`](#rellm-ServerConfiguration) message). `users.proto` deliberately never
  /// imports `server_configuration.proto` (server configuration is kept abstracted from the rest of
  /// the protocol), so this relationship exists only in backend logic
  /// (`contact_verification::contact_protocol_supported`, called from `update_user.rs`) and in this
  /// doc comment, not as a formal schema reference.
  @$pb.TagNumber(3)
  $core.bool get supportedByServer => $_getBF(2);
  @$pb.TagNumber(3)
  set supportedByServer($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSupportedByServer() => $_has(2);
  @$pb.TagNumber(3)
  void clearSupportedByServer() => clearField(3);

  /// Time the contact method was verified. Indicates the user has completed verification of the
  /// contact method. Verification requires `supported_by_server` to be `true`, and is set by
  /// [`VerifyContactMethod`](#grpc-api-VerifyContactMethod) on a correct code.
  @$pb.TagNumber(4)
  $13.Timestamp get verifiedAt => $_getN(3);
  @$pb.TagNumber(4)
  set verifiedAt($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVerifiedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearVerifiedAt() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureVerifiedAt() => $_ensure(3);

  /// Set while an SMS verification code has been sent and not yet confirmed, expired, or exhausted
  /// -- populated by [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification)
  /// and cleared by a successful [`VerifyContactMethod`](#grpc-api-VerifyContactMethod) (which sets
  /// `verified_at` instead) or by expiry/too-many-attempts. See
  /// [`ContactMethodVerification`](#rellm-ContactMethodVerification) for its own fields.
  @$pb.TagNumber(5)
  ContactMethodVerification get verificationInProgress => $_getN(4);
  @$pb.TagNumber(5)
  set verificationInProgress(ContactMethodVerification v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasVerificationInProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearVerificationInProgress() => clearField(5);
  @$pb.TagNumber(5)
  ContactMethodVerification ensureVerificationInProgress() => $_ensure(4);

  /// Whether the user currently consents to being contacted via this `ContactMethod` (e.g. by SMS,
  /// for `tel:` values) by external services -- see `docs/contact_integrations.md`. External
  /// services (Twilio/Bird/Telnyx) may not contact the user unless this is
  /// `CONTACT_CONSENT_GRANTED` -- this includes
  /// [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification)'s own outbound
  /// verification SMS, which fails with `contact_consent_not_granted` until consent is granted,
  /// even though the user is the one requesting the send. Defaults to `CONTACT_CONSENT_REVOKED`
  /// (proto3's zero value) so a `ContactMethod` with no explicit consent action is treated as
  /// not-consented. Settable via the [`UpdateUser`](#grpc-api-UpdateUser) RPC -- same
  /// self-or-`ADMIN` gate as `value`/
  /// `visibility` (see `update_user.rs`'s `admin || self_update` check), not restricted further;
  /// every change appends a new entry to `consent_history` (server-timestamped, never trusted from
  /// client input). Only ever sent to the `ContactMethod`'s own owner or an `ADMIN` -- unlike `value`,
  /// never relaxed by `VIEW_PRIVATE_CONTACT_METHODS`; every other viewer sees this blanked to
  /// `CONTACT_CONSENT_REVOKED` regardless of the `ContactMethod`'s own `visibility`.
  @$pb.TagNumber(6)
  ContactConsentState get consentState => $_getN(5);
  @$pb.TagNumber(6)
  set consentState(ContactConsentState v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasConsentState() => $_has(5);
  @$pb.TagNumber(6)
  void clearConsentState() => clearField(6);

  /// Append-only history of every `consent_state` change, oldest first. Not directly modifiable --
  /// the server appends to it whenever [`UpdateUser`](#grpc-api-UpdateUser) changes `consent_state`,
  /// using the server's own time for
  /// [`ContactConsentChange.changed_at`](#rellm-ContactConsentChange) regardless of what the client
  /// sends. Same owner-or-`ADMIN`-only visibility as `consent_state` (blanked to empty for every
  /// other viewer).
  @$pb.TagNumber(7)
  $core.List<ContactConsentChange> get consentHistory => $_getList(6);
}

/// A single entry in a [`ContactMethod.consent_history`](#rellm-ContactMethod), recording that its
/// `consent_state` became `state` as of `changed_at`. Our ultimate consent state is always the
/// `state` of the most recent (last) entry in `consent_history` --
/// [`ContactMethod.consent_state`](#rellm-ContactMethod) is just a denormalized copy of it, kept
/// for convenient access without walking the history.
class ContactConsentChange extends $pb.GeneratedMessage {
  factory ContactConsentChange({
    ContactConsentState? state,
    $13.Timestamp? changedAt,
  }) {
    final $result = create();
    if (state != null) {
      $result.state = state;
    }
    if (changedAt != null) {
      $result.changedAt = changedAt;
    }
    return $result;
  }
  ContactConsentChange._() : super();
  factory ContactConsentChange.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactConsentChange.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactConsentChange', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..e<ContactConsentState>(1, _omitFieldNames ? '' : 'state', $pb.PbFieldType.OE, defaultOrMaker: ContactConsentState.CONTACT_CONSENT_REVOKED, valueOf: ContactConsentState.valueOf, enumValues: ContactConsentState.values)
    ..aOM<$13.Timestamp>(2, _omitFieldNames ? '' : 'changedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactConsentChange clone() => ContactConsentChange()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactConsentChange copyWith(void Function(ContactConsentChange) updates) => super.copyWith((message) => updates(message as ContactConsentChange)) as ContactConsentChange;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactConsentChange create() => ContactConsentChange._();
  ContactConsentChange createEmptyInstance() => create();
  static $pb.PbList<ContactConsentChange> createRepeated() => $pb.PbList<ContactConsentChange>();
  @$core.pragma('dart2js:noInline')
  static ContactConsentChange getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactConsentChange>(create);
  static ContactConsentChange? _defaultInstance;

  /// The [`ContactConsentState`](#rellm-ContactConsentState) the `ContactMethod` was changed to.
  @$pb.TagNumber(1)
  ContactConsentState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(ContactConsentState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => clearField(1);

  /// When this change took effect. Always the server's own time as of the
  /// [`UpdateUser`](#grpc-api-UpdateUser) call that made the change -- any `changed_at` sent by a
  /// client is ignored.
  @$pb.TagNumber(2)
  $13.Timestamp get changedAt => $_getN(1);
  @$pb.TagNumber(2)
  set changedAt($13.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasChangedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearChangedAt() => clearField(2);
  @$pb.TagNumber(2)
  $13.Timestamp ensureChangedAt() => $_ensure(1);
}

/// Encapsulates verification of a [`ContactMethod`](#rellm-ContactMethod). Verification cannot
/// begin until contact consent (`ContactMethod.consent_state`) is granted -- see
/// [`StartContactMethodVerification`](#grpc-api-StartContactMethodVerification).
class ContactMethodVerification extends $pb.GeneratedMessage {
  factory ContactMethodVerification({
    $core.String? verificationCode,
    $13.Timestamp? verificationStartedAt,
    $core.int? attempts,
  }) {
    final $result = create();
    if (verificationCode != null) {
      $result.verificationCode = verificationCode;
    }
    if (verificationStartedAt != null) {
      $result.verificationStartedAt = verificationStartedAt;
    }
    if (attempts != null) {
      $result.attempts = attempts;
    }
    return $result;
  }
  ContactMethodVerification._() : super();
  factory ContactMethodVerification.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactMethodVerification.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactMethodVerification', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'verificationCode')
    ..aOM<$13.Timestamp>(2, _omitFieldNames ? '' : 'verificationStartedAt', subBuilder: $13.Timestamp.create)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'attempts', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactMethodVerification clone() => ContactMethodVerification()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactMethodVerification copyWith(void Function(ContactMethodVerification) updates) => super.copyWith((message) => updates(message as ContactMethodVerification)) as ContactMethodVerification;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactMethodVerification create() => ContactMethodVerification._();
  ContactMethodVerification createEmptyInstance() => create();
  static $pb.PbList<ContactMethodVerification> createRepeated() => $pb.PbList<ContactMethodVerification>();
  @$core.pragma('dart2js:noInline')
  static ContactMethodVerification getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactMethodVerification>(create);
  static ContactMethodVerification? _defaultInstance;

  /// Never serialized to gRPC by the backend. Only stored server-side; a client's own attempt to
  /// verify goes through [`VerifyContactMethodRequest.code`](#rellm-VerifyContactMethodRequest)
  /// instead, not this field.
  @$pb.TagNumber(1)
  $core.String get verificationCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set verificationCode($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVerificationCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearVerificationCode() => clearField(1);

  @$pb.TagNumber(2)
  $13.Timestamp get verificationStartedAt => $_getN(1);
  @$pb.TagNumber(2)
  set verificationStartedAt($13.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasVerificationStartedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearVerificationStartedAt() => clearField(2);
  @$pb.TagNumber(2)
  $13.Timestamp ensureVerificationStartedAt() => $_ensure(1);

  /// Number of failed [`VerifyContactMethod`](#grpc-api-VerifyContactMethod) attempts against
  /// `verification_code` since it was sent. Capped (see that RPC's own doc) to prevent
  /// brute-forcing the 6-digit code within its expiry window.
  @$pb.TagNumber(3)
  $core.int get attempts => $_getIZ(2);
  @$pb.TagNumber(3)
  set attempts($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAttempts() => $_has(2);
  @$pb.TagNumber(3)
  void clearAttempts() => clearField(3);
}

///  Request to get one or more users by a variety of parameters.
///  Supported parameters depend on `listing_type`.
///
///  - `{listing_type: USERS_TEXT_SEARCH, search_text:}`
///      - Full-text search across accessible users' username, real name, and bio.
///  - `{listing_type: FOLLOWERS_TEXT_SEARCH, search_text:, user_id:}` (and the
///    `FOLLOWING_TEXT_SEARCH`/`FRIENDS_TEXT_SEARCH`/`FOLLOW_REQUESTS_TEXT_SEARCH` equivalents)
///      - Scopes that same full-text search to `user_id`'s followers/following/friends/follow
///        requests, same relationship rules as the non-search `listing_type`.
class GetUsersRequest extends $pb.GeneratedMessage {
  factory GetUsersRequest({
    $core.String? username,
    $core.String? userId,
    $core.String? searchText,
    $core.int? page,
    UserListingType? listingType,
  }) {
    final $result = create();
    if (username != null) {
      $result.username = username;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (searchText != null) {
      $result.searchText = searchText;
    }
    if (page != null) {
      $result.page = page;
    }
    if (listingType != null) {
      $result.listingType = listingType;
    }
    return $result;
  }
  GetUsersRequest._() : super();
  factory GetUsersRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetUsersRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetUsersRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'searchText')
    ..a<$core.int>(99, _omitFieldNames ? '' : 'page', $pb.PbFieldType.O3)
    ..e<UserListingType>(100, _omitFieldNames ? '' : 'listingType', $pb.PbFieldType.OE, defaultOrMaker: UserListingType.EVERYONE, valueOf: UserListingType.valueOf, enumValues: UserListingType.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetUsersRequest clone() => GetUsersRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetUsersRequest copyWith(void Function(GetUsersRequest) updates) => super.copyWith((message) => updates(message as GetUsersRequest)) as GetUsersRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetUsersRequest create() => GetUsersRequest._();
  GetUsersRequest createEmptyInstance() => create();
  static $pb.PbList<GetUsersRequest> createRepeated() => $pb.PbList<GetUsersRequest>();
  @$core.pragma('dart2js:noInline')
  static GetUsersRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetUsersRequest>(create);
  static GetUsersRequest? _defaultInstance;

  /// The username to search for. Substrings are supported.
  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => clearField(1);

  /// The user ID to search for.
  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);

  /// Full-text search query, matched against the user's username/real name/bio. Required (and
  /// only used) when `listing_type` is `USERS_TEXT_SEARCH` or one of the `*_TEXT_SEARCH` variants.
  @$pb.TagNumber(3)
  $core.String get searchText => $_getSZ(2);
  @$pb.TagNumber(3)
  set searchText($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSearchText() => $_has(2);
  @$pb.TagNumber(3)
  void clearSearchText() => clearField(3);

  /// The page of results to return. Pages are 0-indexed.
  @$pb.TagNumber(99)
  $core.int get page => $_getIZ(3);
  @$pb.TagNumber(99)
  set page($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(99)
  $core.bool hasPage() => $_has(3);
  @$pb.TagNumber(99)
  void clearPage() => clearField(99);

  /// The number of results to return per page.
  @$pb.TagNumber(100)
  UserListingType get listingType => $_getN(4);
  @$pb.TagNumber(100)
  set listingType(UserListingType v) { setField(100, v); }
  @$pb.TagNumber(100)
  $core.bool hasListingType() => $_has(4);
  @$pb.TagNumber(100)
  void clearListingType() => clearField(100);
}

/// Response to a [`GetUsersRequest`](#rellm-GetUsersRequest).
class GetUsersResponse extends $pb.GeneratedMessage {
  factory GetUsersResponse({
    $core.Iterable<User>? users,
    $core.bool? hasNextPage,
  }) {
    final $result = create();
    if (users != null) {
      $result.users.addAll(users);
    }
    if (hasNextPage != null) {
      $result.hasNextPage = hasNextPage;
    }
    return $result;
  }
  GetUsersResponse._() : super();
  factory GetUsersResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetUsersResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetUsersResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<User>(1, _omitFieldNames ? '' : 'users', $pb.PbFieldType.PM, subBuilder: User.create)
    ..aOB(2, _omitFieldNames ? '' : 'hasNextPage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetUsersResponse clone() => GetUsersResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetUsersResponse copyWith(void Function(GetUsersResponse) updates) => super.copyWith((message) => updates(message as GetUsersResponse)) as GetUsersResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetUsersResponse create() => GetUsersResponse._();
  GetUsersResponse createEmptyInstance() => create();
  static $pb.PbList<GetUsersResponse> createRepeated() => $pb.PbList<GetUsersResponse>();
  @$core.pragma('dart2js:noInline')
  static GetUsersResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetUsersResponse>(create);
  static GetUsersResponse? _defaultInstance;

  /// The users matching the request.
  @$pb.TagNumber(1)
  $core.List<User> get users => $_getList(0);

  /// Whether there are more pages of results.
  @$pb.TagNumber(2)
  $core.bool get hasNextPage => $_getBF(1);
  @$pb.TagNumber(2)
  set hasNextPage($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHasNextPage() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasNextPage() => clearField(2);
}

/// Request for [`VerifyContactMethod`](#grpc-api-VerifyContactMethod).
class VerifyContactMethodRequest extends $pb.GeneratedMessage {
  factory VerifyContactMethodRequest({
    $core.String? value,
    $core.String? code,
  }) {
    final $result = create();
    if (value != null) {
      $result.value = value;
    }
    if (code != null) {
      $result.code = code;
    }
    return $result;
  }
  VerifyContactMethodRequest._() : super();
  factory VerifyContactMethodRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VerifyContactMethodRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VerifyContactMethodRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VerifyContactMethodRequest clone() => VerifyContactMethodRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VerifyContactMethodRequest copyWith(void Function(VerifyContactMethodRequest) updates) => super.copyWith((message) => updates(message as VerifyContactMethodRequest)) as VerifyContactMethodRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VerifyContactMethodRequest create() => VerifyContactMethodRequest._();
  VerifyContactMethodRequest createEmptyInstance() => create();
  static $pb.PbList<VerifyContactMethodRequest> createRepeated() => $pb.PbList<VerifyContactMethodRequest>();
  @$core.pragma('dart2js:noInline')
  static VerifyContactMethodRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VerifyContactMethodRequest>(create);
  static VerifyContactMethodRequest? _defaultInstance;

  /// The `tel:` (or, in the future, `mailto:`) value being verified -- must match the current
  /// user's own stored `phone`/`email` value.
  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => clearField(1);

  /// The code the user was sent by `StartContactMethodVerification`.
  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
