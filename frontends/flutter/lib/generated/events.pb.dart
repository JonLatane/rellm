//
//  Generated code. Do not modify.
//  source: events.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'events.pbenum.dart';
import 'google/protobuf/timestamp.pb.dart' as $13;
import 'location.pb.dart' as $16;
import 'media.pb.dart' as $5;
import 'permissions.pbenum.dart' as $15;
import 'posts.pb.dart' as $8;
import 'sync.pb.dart' as $10;
import 'users.pb.dart' as $4;
import 'visibility_moderation.pbenum.dart' as $14;

export 'events.pbenum.dart';

///  Request to get Events in a formatted *per-Occasion* structure. i.e. the response will carry duplicate [`Event`](#rellm-Event)s with the same ID
///  if that [`Event`](#rellm-Event) has multiple [`Occasion`](#rellm-Occasion)s in the time frame the client asked for.
///
///  These structured Occasions are ordered by start time unless otherwise specified (specifically, `EventListingType.NEWLY_ADDED_EVENTS`).
///
///  Valid GetEventsRequest formats:
///  - `{[listing_type: PublicEvents]}`                 (TODO: get ServerPublic/GlobalPublic events you can see)
///  - `{listing_type:MyGroupsEvents|FollowingEvents}`  (TODO: get events for groups joined or user followed; auth required)
///  - `{post_id:}`                                     (get a single event, by its own Post ID or one of its Occasions' Post IDs)
///  - `{listing_type: GroupEvents| GroupEventsPendingModeration, group_id:}`
///                                                     (TODO: get events/events needing moderation for a group)
///  - `{author_user_id:, group_id:}`                   (TODO: get events by a user for a group)
///  - `{listing_type: AuthorEvents, author_user_id:}`  (TODO: get events by a user)
class GetEventsRequest extends $pb.GeneratedMessage {
  factory GetEventsRequest({
    $core.String? authorUserId,
    $core.String? groupId,
    TimeFilter? timeFilter,
    $core.String? attendeeId,
    $core.Iterable<AttendanceStatus>? attendanceStatuses,
    $core.String? postId,
    EventListingType? listingType,
    $core.String? searchText,
    $core.Iterable<$core.String>? occasionPostIds,
    $core.String? anonymousAttendeeAuthToken,
  }) {
    final $result = create();
    if (authorUserId != null) {
      $result.authorUserId = authorUserId;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (timeFilter != null) {
      $result.timeFilter = timeFilter;
    }
    if (attendeeId != null) {
      $result.attendeeId = attendeeId;
    }
    if (attendanceStatuses != null) {
      $result.attendanceStatuses.addAll(attendanceStatuses);
    }
    if (postId != null) {
      $result.postId = postId;
    }
    if (listingType != null) {
      $result.listingType = listingType;
    }
    if (searchText != null) {
      $result.searchText = searchText;
    }
    if (occasionPostIds != null) {
      $result.occasionPostIds.addAll(occasionPostIds);
    }
    if (anonymousAttendeeAuthToken != null) {
      $result.anonymousAttendeeAuthToken = anonymousAttendeeAuthToken;
    }
    return $result;
  }
  GetEventsRequest._() : super();
  factory GetEventsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetEventsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetEventsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'authorUserId')
    ..aOS(3, _omitFieldNames ? '' : 'groupId')
    ..aOM<TimeFilter>(5, _omitFieldNames ? '' : 'timeFilter', subBuilder: TimeFilter.create)
    ..aOS(6, _omitFieldNames ? '' : 'attendeeId')
    ..pc<AttendanceStatus>(7, _omitFieldNames ? '' : 'attendanceStatuses', $pb.PbFieldType.KE, valueOf: AttendanceStatus.valueOf, enumValues: AttendanceStatus.values, defaultEnumValue: AttendanceStatus.INTERESTED)
    ..aOS(8, _omitFieldNames ? '' : 'postId')
    ..e<EventListingType>(10, _omitFieldNames ? '' : 'listingType', $pb.PbFieldType.OE, defaultOrMaker: EventListingType.ALL_ACCESSIBLE_EVENTS, valueOf: EventListingType.valueOf, enumValues: EventListingType.values)
    ..aOS(11, _omitFieldNames ? '' : 'searchText')
    ..pPS(12, _omitFieldNames ? '' : 'occasionPostIds')
    ..aOS(13, _omitFieldNames ? '' : 'anonymousAttendeeAuthToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetEventsRequest clone() => GetEventsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetEventsRequest copyWith(void Function(GetEventsRequest) updates) => super.copyWith((message) => updates(message as GetEventsRequest)) as GetEventsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetEventsRequest create() => GetEventsRequest._();
  GetEventsRequest createEmptyInstance() => create();
  static $pb.PbList<GetEventsRequest> createRepeated() => $pb.PbList<GetEventsRequest>();
  @$core.pragma('dart2js:noInline')
  static GetEventsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetEventsRequest>(create);
  static GetEventsRequest? _defaultInstance;

  /// Limits results to those by the given author user ID.
  @$pb.TagNumber(2)
  $core.String get authorUserId => $_getSZ(0);
  @$pb.TagNumber(2)
  set authorUserId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasAuthorUserId() => $_has(0);
  @$pb.TagNumber(2)
  void clearAuthorUserId() => clearField(2);

  /// Limits results to those in the given group ID (via [`GroupPost`](#rellm-GroupPost) association's for the Event's internal [`Post`](#rellm-Post)).
  @$pb.TagNumber(3)
  $core.String get groupId => $_getSZ(1);
  @$pb.TagNumber(3)
  set groupId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasGroupId() => $_has(1);
  @$pb.TagNumber(3)
  void clearGroupId() => clearField(3);

  /// Filters returned [`Occasion`](#rellm-Occasion)s by time.
  @$pb.TagNumber(5)
  TimeFilter get timeFilter => $_getN(2);
  @$pb.TagNumber(5)
  set timeFilter(TimeFilter v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimeFilter() => $_has(2);
  @$pb.TagNumber(5)
  void clearTimeFilter() => clearField(5);
  @$pb.TagNumber(5)
  TimeFilter ensureTimeFilter() => $_ensure(2);

  /// If set, only returns events that the given user is attending. If `attendance_statuses` is also set,
  /// returns events where that user's status is one of the given statuses.
  @$pb.TagNumber(6)
  $core.String get attendeeId => $_getSZ(3);
  @$pb.TagNumber(6)
  set attendeeId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(6)
  $core.bool hasAttendeeId() => $_has(3);
  @$pb.TagNumber(6)
  void clearAttendeeId() => clearField(6);

  /// If set, only return events for which the current user's attendance status matches one of the given statuses. If `attendee_id` is also set,
  /// only returns events where the given user's status matches one of the given statuses.
  @$pb.TagNumber(7)
  $core.List<AttendanceStatus> get attendanceStatuses => $_getList(4);

  /// Finds Events for the Post with the given ID. The Post should have a [`PostContext`](#rellm-PostContext) of `EVENT` or `OCCASION`.
  @$pb.TagNumber(8)
  $core.String get postId => $_getSZ(5);
  @$pb.TagNumber(8)
  set postId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(8)
  $core.bool hasPostId() => $_has(5);
  @$pb.TagNumber(8)
  void clearPostId() => clearField(8);

  /// The listing type, e.g. `ALL_ACCESSIBLE_EVENTS`, `FOLLOWING_EVENTS`, `MY_GROUPS_EVENTS`, `DIRECT_EVENTS`, `GROUP_EVENTS`, `GROUP_EVENTS_PENDING_MODERATION`.
  @$pb.TagNumber(10)
  EventListingType get listingType => $_getN(6);
  @$pb.TagNumber(10)
  set listingType(EventListingType v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasListingType() => $_has(6);
  @$pb.TagNumber(10)
  void clearListingType() => clearField(10);

  /// Search text for full-text search.
  @$pb.TagNumber(11)
  $core.String get searchText => $_getSZ(7);
  @$pb.TagNumber(11)
  set searchText($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(11)
  $core.bool hasSearchText() => $_has(7);
  @$pb.TagNumber(11)
  void clearSearchText() => clearField(11);

  /// Loads multiple events by their occasions' Post IDs - returns one
  /// Event per matching Occasion (see GetEventsResponse's own doc), not
  /// the requested Occasion's whole parent Event's full occasion list.
  @$pb.TagNumber(12)
  $core.List<$core.String> get occasionPostIds => $_getList(8);

  /// Auth token proving ownership of an anonymous RSVP, mirroring
  /// `GetEventAttendancesRequest.anonymous_attendee_auth_token`. Lets an anonymous attendee's own
  /// (possibly still-`PENDING`) [`EventAttendance`](#rellm-EventAttendance) and its `Occasion.location` (when
  /// `EventInfo.hide_location_until_rsvp_approved` is set) surface via each returned
  /// `Occasion.attendances`/`current_user_attendance`, same as a logged-in user's own RSVP
  /// does automatically.
  @$pb.TagNumber(13)
  $core.String get anonymousAttendeeAuthToken => $_getSZ(9);
  @$pb.TagNumber(13)
  set anonymousAttendeeAuthToken($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(13)
  $core.bool hasAnonymousAttendeeAuthToken() => $_has(9);
  @$pb.TagNumber(13)
  void clearAnonymousAttendeeAuthToken() => clearField(13);
}

/// Time filter that works on the `starts_at` and `ends_at` fields of [`Occasion`](#rellm-Occasion).
/// API currently only supports `ends_after`.
class TimeFilter extends $pb.GeneratedMessage {
  factory TimeFilter({
    $13.Timestamp? startsAfter,
    $13.Timestamp? endsAfter,
    $13.Timestamp? startsBefore,
    $13.Timestamp? endsBefore,
  }) {
    final $result = create();
    if (startsAfter != null) {
      $result.startsAfter = startsAfter;
    }
    if (endsAfter != null) {
      $result.endsAfter = endsAfter;
    }
    if (startsBefore != null) {
      $result.startsBefore = startsBefore;
    }
    if (endsBefore != null) {
      $result.endsBefore = endsBefore;
    }
    return $result;
  }
  TimeFilter._() : super();
  factory TimeFilter.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TimeFilter.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TimeFilter', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<$13.Timestamp>(1, _omitFieldNames ? '' : 'startsAfter', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(2, _omitFieldNames ? '' : 'endsAfter', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(3, _omitFieldNames ? '' : 'startsBefore', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'endsBefore', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TimeFilter clone() => TimeFilter()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TimeFilter copyWith(void Function(TimeFilter) updates) => super.copyWith((message) => updates(message as TimeFilter)) as TimeFilter;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TimeFilter create() => TimeFilter._();
  TimeFilter createEmptyInstance() => create();
  static $pb.PbList<TimeFilter> createRepeated() => $pb.PbList<TimeFilter>();
  @$core.pragma('dart2js:noInline')
  static TimeFilter getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TimeFilter>(create);
  static TimeFilter? _defaultInstance;

  /// Filter to events that start after the given time.
  @$pb.TagNumber(1)
  $13.Timestamp get startsAfter => $_getN(0);
  @$pb.TagNumber(1)
  set startsAfter($13.Timestamp v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasStartsAfter() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartsAfter() => clearField(1);
  @$pb.TagNumber(1)
  $13.Timestamp ensureStartsAfter() => $_ensure(0);

  /// Filter to events that end after the given time.
  @$pb.TagNumber(2)
  $13.Timestamp get endsAfter => $_getN(1);
  @$pb.TagNumber(2)
  set endsAfter($13.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasEndsAfter() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndsAfter() => clearField(2);
  @$pb.TagNumber(2)
  $13.Timestamp ensureEndsAfter() => $_ensure(1);

  /// Filter to events that start before the given time.
  @$pb.TagNumber(3)
  $13.Timestamp get startsBefore => $_getN(2);
  @$pb.TagNumber(3)
  set startsBefore($13.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasStartsBefore() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartsBefore() => clearField(3);
  @$pb.TagNumber(3)
  $13.Timestamp ensureStartsBefore() => $_ensure(2);

  /// Filter to events that end before the given time.
  @$pb.TagNumber(4)
  $13.Timestamp get endsBefore => $_getN(3);
  @$pb.TagNumber(4)
  set endsBefore($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasEndsBefore() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndsBefore() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureEndsBefore() => $_ensure(3);
}

///  A list of [`Event`](#rellm-Event)s with a maybe-incomplete (see [`GetEventsRequest`](#rellm-GetEventsRequest)) set of their [`Occasion`](#rellm-Occasion)s.
///
///  Note that `GetEventsResponse` may often include duplicate Events with the same ID.
///  I.E. something like: `{events: [{id: a, occasions: [{id: x}]}, {id: a, occasions: [{id: y}]}, ]}` is a valid response.
///  This semantically means: "Event A has both occasions X and Y in the time frame the client asked for."
///  The client should be able to handle this.
///
///  In the React/Tamagui client, this is handled by the Redux store, which
///  effectively "compacts" all response into its own internal Events store, in a form something like:
///  `{events: {a: {id: a, occasions: [{id: x}, {id: y}]}, ...}, occasionEventIds: {x:a, y:a}}`.
///  (In reality it uses `EntityAdapter` which is a bit more complicated, but the idea is the same.)
class GetEventsResponse extends $pb.GeneratedMessage {
  factory GetEventsResponse({
    $core.Iterable<Event>? events,
  }) {
    final $result = create();
    if (events != null) {
      $result.events.addAll(events);
    }
    return $result;
  }
  GetEventsResponse._() : super();
  factory GetEventsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetEventsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetEventsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<Event>(1, _omitFieldNames ? '' : 'events', $pb.PbFieldType.PM, subBuilder: Event.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetEventsResponse clone() => GetEventsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetEventsResponse copyWith(void Function(GetEventsResponse) updates) => super.copyWith((message) => updates(message as GetEventsResponse)) as GetEventsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetEventsResponse create() => GetEventsResponse._();
  GetEventsResponse createEmptyInstance() => create();
  static $pb.PbList<GetEventsResponse> createRepeated() => $pb.PbList<GetEventsResponse>();
  @$core.pragma('dart2js:noInline')
  static GetEventsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetEventsResponse>(create);
  static GetEventsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<Event> get events => $_getList(0);
}

///  An `Event` is a top-level type used to organize calendar events, RSVPs, and messaging/posting
///  about the `Event`. Actual time data lies in its `Occasions`.
///
///  (Eventually, Rellm Events should also support ticketing.)
class Event extends $pb.GeneratedMessage {
  factory Event({
    $8.Post? post,
    EventInfo? info,
    $core.Iterable<Occasion>? occasions,
  }) {
    final $result = create();
    if (post != null) {
      $result.post = post;
    }
    if (info != null) {
      $result.info = info;
    }
    if (occasions != null) {
      $result.occasions.addAll(occasions);
    }
    return $result;
  }
  Event._() : super();
  factory Event.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Event.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Event', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<$8.Post>(2, _omitFieldNames ? '' : 'post', subBuilder: $8.Post.create)
    ..aOM<EventInfo>(3, _omitFieldNames ? '' : 'info', subBuilder: EventInfo.create)
    ..pc<Occasion>(4, _omitFieldNames ? '' : 'occasions', $pb.PbFieldType.PM, subBuilder: Occasion.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Event clone() => Event()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Event copyWith(void Function(Event) updates) => super.copyWith((message) => updates(message as Event)) as Event;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Event create() => Event._();
  Event createEmptyInstance() => create();
  static $pb.PbList<Event> createRepeated() => $pb.PbList<Event>();
  @$core.pragma('dart2js:noInline')
  static Event getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Event>(create);
  static Event? _defaultInstance;

  /// The Post containing the underlying data for the event (title, content, moderation, visibility, etc.). Its [`PostContext`](#rellm-PostContext) should be `EVENT`.
  /// An `Event`'s ID *is* its `post.id` - there is no separate surrogate ID.
  @$pb.TagNumber(2)
  $8.Post get post => $_getN(0);
  @$pb.TagNumber(2)
  set post($8.Post v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasPost() => $_has(0);
  @$pb.TagNumber(2)
  void clearPost() => clearField(2);
  @$pb.TagNumber(2)
  $8.Post ensurePost() => $_ensure(0);

  /// Event configuration like whether to allow (anonymous) RSVPs, etc.
  @$pb.TagNumber(3)
  EventInfo get info => $_getN(1);
  @$pb.TagNumber(3)
  set info(EventInfo v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasInfo() => $_has(1);
  @$pb.TagNumber(3)
  void clearInfo() => clearField(3);
  @$pb.TagNumber(3)
  EventInfo ensureInfo() => $_ensure(1);

  /// A list of occasions for the Event. *Events will only include all occasions if the request is for a single event.*
  @$pb.TagNumber(4)
  $core.List<Occasion> get occasions => $_getList(2);
}

/// Syncs (cross-posts) a single Occasion to one SyncDestination.
class SyncOccasionRequest extends $pb.GeneratedMessage {
  factory SyncOccasionRequest({
    $core.String? occasionId,
    $core.String? syncDestinationId,
  }) {
    final $result = create();
    if (occasionId != null) {
      $result.occasionId = occasionId;
    }
    if (syncDestinationId != null) {
      $result.syncDestinationId = syncDestinationId;
    }
    return $result;
  }
  SyncOccasionRequest._() : super();
  factory SyncOccasionRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SyncOccasionRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SyncOccasionRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'occasionId')
    ..aOS(2, _omitFieldNames ? '' : 'syncDestinationId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SyncOccasionRequest clone() => SyncOccasionRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SyncOccasionRequest copyWith(void Function(SyncOccasionRequest) updates) => super.copyWith((message) => updates(message as SyncOccasionRequest)) as SyncOccasionRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SyncOccasionRequest create() => SyncOccasionRequest._();
  SyncOccasionRequest createEmptyInstance() => create();
  static $pb.PbList<SyncOccasionRequest> createRepeated() => $pb.PbList<SyncOccasionRequest>();
  @$core.pragma('dart2js:noInline')
  static SyncOccasionRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncOccasionRequest>(create);
  static SyncOccasionRequest? _defaultInstance;

  /// The Occasion to sync.
  @$pb.TagNumber(1)
  $core.String get occasionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set occasionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOccasionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOccasionId() => clearField(1);

  /// The SyncDestination to sync it to.
  @$pb.TagNumber(2)
  $core.String get syncDestinationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set syncDestinationId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSyncDestinationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSyncDestinationId() => clearField(2);
}

/// Removes a single Occasion's sync (cross-post) to one SyncDestination - the reverse of [`SyncOccasion`](#grpc-api-SyncOccasion).
/// Does not delete the post already made on the destination (e.g. the Facebook Page post), only the local sync record.
class DeleteOccasionSyncDestinationRequest extends $pb.GeneratedMessage {
  factory DeleteOccasionSyncDestinationRequest({
    $core.String? occasionId,
    $core.String? syncDestinationId,
  }) {
    final $result = create();
    if (occasionId != null) {
      $result.occasionId = occasionId;
    }
    if (syncDestinationId != null) {
      $result.syncDestinationId = syncDestinationId;
    }
    return $result;
  }
  DeleteOccasionSyncDestinationRequest._() : super();
  factory DeleteOccasionSyncDestinationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeleteOccasionSyncDestinationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeleteOccasionSyncDestinationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'occasionId')
    ..aOS(2, _omitFieldNames ? '' : 'syncDestinationId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeleteOccasionSyncDestinationRequest clone() => DeleteOccasionSyncDestinationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeleteOccasionSyncDestinationRequest copyWith(void Function(DeleteOccasionSyncDestinationRequest) updates) => super.copyWith((message) => updates(message as DeleteOccasionSyncDestinationRequest)) as DeleteOccasionSyncDestinationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteOccasionSyncDestinationRequest create() => DeleteOccasionSyncDestinationRequest._();
  DeleteOccasionSyncDestinationRequest createEmptyInstance() => create();
  static $pb.PbList<DeleteOccasionSyncDestinationRequest> createRepeated() => $pb.PbList<DeleteOccasionSyncDestinationRequest>();
  @$core.pragma('dart2js:noInline')
  static DeleteOccasionSyncDestinationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteOccasionSyncDestinationRequest>(create);
  static DeleteOccasionSyncDestinationRequest? _defaultInstance;

  /// The Occasion to un-sync.
  @$pb.TagNumber(1)
  $core.String get occasionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set occasionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOccasionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOccasionId() => clearField(1);

  /// The SyncDestination to un-sync it from.
  @$pb.TagNumber(2)
  $core.String get syncDestinationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set syncDestinationId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSyncDestinationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSyncDestinationId() => clearField(2);
}

/// To be used for ticketing, RSVPs, etc.
/// Stored as JSON in the database.
class EventInfo extends $pb.GeneratedMessage {
  factory EventInfo({
    $core.bool? allowsRsvps,
    $core.bool? allowsAnonymousRsvps,
    $core.int? maxAttendees,
    $core.bool? hideLocationUntilRsvpApproved,
    $14.Moderation? defaultRsvpModeration,
  }) {
    final $result = create();
    if (allowsRsvps != null) {
      $result.allowsRsvps = allowsRsvps;
    }
    if (allowsAnonymousRsvps != null) {
      $result.allowsAnonymousRsvps = allowsAnonymousRsvps;
    }
    if (maxAttendees != null) {
      $result.maxAttendees = maxAttendees;
    }
    if (hideLocationUntilRsvpApproved != null) {
      $result.hideLocationUntilRsvpApproved = hideLocationUntilRsvpApproved;
    }
    if (defaultRsvpModeration != null) {
      $result.defaultRsvpModeration = defaultRsvpModeration;
    }
    return $result;
  }
  EventInfo._() : super();
  factory EventInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EventInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EventInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'allowsRsvps')
    ..aOB(2, _omitFieldNames ? '' : 'allowsAnonymousRsvps')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxAttendees', $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'hideLocationUntilRsvpApproved')
    ..e<$14.Moderation>(5, _omitFieldNames ? '' : 'defaultRsvpModeration', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EventInfo clone() => EventInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EventInfo copyWith(void Function(EventInfo) updates) => super.copyWith((message) => updates(message as EventInfo)) as EventInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventInfo create() => EventInfo._();
  EventInfo createEmptyInstance() => create();
  static $pb.PbList<EventInfo> createRepeated() => $pb.PbList<EventInfo>();
  @$core.pragma('dart2js:noInline')
  static EventInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EventInfo>(create);
  static EventInfo? _defaultInstance;

  /// Whether to allow RSVPs for the event.
  @$pb.TagNumber(1)
  $core.bool get allowsRsvps => $_getBF(0);
  @$pb.TagNumber(1)
  set allowsRsvps($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllowsRsvps() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllowsRsvps() => clearField(1);

  /// Whether to allow anonymous RSVPs for the event.
  @$pb.TagNumber(2)
  $core.bool get allowsAnonymousRsvps => $_getBF(1);
  @$pb.TagNumber(2)
  set allowsAnonymousRsvps($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAllowsAnonymousRsvps() => $_has(1);
  @$pb.TagNumber(2)
  void clearAllowsAnonymousRsvps() => clearField(2);

  /// Limit the max number of attendees. No effect unless `allows_rsvps` is true. Not yet supported.
  @$pb.TagNumber(3)
  $core.int get maxAttendees => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxAttendees($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxAttendees() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxAttendees() => clearField(3);

  /// Hide the location until the user RSVPs (and it's accepted).
  /// From a system perspective, when this is set, Events will not include the [`Location`](#rellm-Location) until the user has RSVP'd.
  /// Location will always be returned in EventAttendances if the request for the EventAttendances came from a (logged in or anonymous)
  /// user whose attendance is approved (or the event owner).
  @$pb.TagNumber(4)
  $core.bool get hideLocationUntilRsvpApproved => $_getBF(3);
  @$pb.TagNumber(4)
  set hideLocationUntilRsvpApproved($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHideLocationUntilRsvpApproved() => $_has(3);
  @$pb.TagNumber(4)
  void clearHideLocationUntilRsvpApproved() => clearField(4);

  /// Default moderation for RSVPs from logged-in users (either `PENDING` or `APPROVED`).
  /// Anonymous RSVPs are always moderated (default to `PENDING`).
  @$pb.TagNumber(5)
  $14.Moderation get defaultRsvpModeration => $_getN(4);
  @$pb.TagNumber(5)
  set defaultRsvpModeration($14.Moderation v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasDefaultRsvpModeration() => $_has(4);
  @$pb.TagNumber(5)
  void clearDefaultRsvpModeration() => clearField(5);
}

/// The time-based component of an [`Event`](#rellm-Event). Has a `starts_at` and `ends_at` time,
/// a [`Location`](#rellm-Location), and an optional [`Post`](#rellm-Post) (and discussion thread) specific to this particular
/// `Occasion` in addition to the parent [`Event`](#rellm-Event).
class Occasion extends $pb.GeneratedMessage {
  factory Occasion({
    $core.String? eventId,
    $8.Post? post,
    OccasionInfo? info,
    $13.Timestamp? startsAt,
    $13.Timestamp? endsAt,
    $16.Location? location,
    $13.Timestamp? syncMissingSince,
    EventAttendances? attendances,
    EventAttendance? currentUserAttendance,
    $core.Iterable<$10.SyncDestinationStatus>? syncDestinations,
    $core.String? timezone,
  }) {
    final $result = create();
    if (eventId != null) {
      $result.eventId = eventId;
    }
    if (post != null) {
      $result.post = post;
    }
    if (info != null) {
      $result.info = info;
    }
    if (startsAt != null) {
      $result.startsAt = startsAt;
    }
    if (endsAt != null) {
      $result.endsAt = endsAt;
    }
    if (location != null) {
      $result.location = location;
    }
    if (syncMissingSince != null) {
      $result.syncMissingSince = syncMissingSince;
    }
    if (attendances != null) {
      $result.attendances = attendances;
    }
    if (currentUserAttendance != null) {
      $result.currentUserAttendance = currentUserAttendance;
    }
    if (syncDestinations != null) {
      $result.syncDestinations.addAll(syncDestinations);
    }
    if (timezone != null) {
      $result.timezone = timezone;
    }
    return $result;
  }
  Occasion._() : super();
  factory Occasion.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Occasion.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Occasion', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'eventId')
    ..aOM<$8.Post>(3, _omitFieldNames ? '' : 'post', subBuilder: $8.Post.create)
    ..aOM<OccasionInfo>(4, _omitFieldNames ? '' : 'info', subBuilder: OccasionInfo.create)
    ..aOM<$13.Timestamp>(5, _omitFieldNames ? '' : 'startsAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(6, _omitFieldNames ? '' : 'endsAt', subBuilder: $13.Timestamp.create)
    ..aOM<$16.Location>(7, _omitFieldNames ? '' : 'location', subBuilder: $16.Location.create)
    ..aOM<$13.Timestamp>(9, _omitFieldNames ? '' : 'syncMissingSince', subBuilder: $13.Timestamp.create)
    ..aOM<EventAttendances>(10, _omitFieldNames ? '' : 'attendances', subBuilder: EventAttendances.create)
    ..aOM<EventAttendance>(11, _omitFieldNames ? '' : 'currentUserAttendance', subBuilder: EventAttendance.create)
    ..pc<$10.SyncDestinationStatus>(12, _omitFieldNames ? '' : 'syncDestinations', $pb.PbFieldType.PM, subBuilder: $10.SyncDestinationStatus.create)
    ..aOS(13, _omitFieldNames ? '' : 'timezone')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Occasion clone() => Occasion()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Occasion copyWith(void Function(Occasion) updates) => super.copyWith((message) => updates(message as Occasion)) as Occasion;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Occasion create() => Occasion._();
  Occasion createEmptyInstance() => create();
  static $pb.PbList<Occasion> createRepeated() => $pb.PbList<Occasion>();
  @$core.pragma('dart2js:noInline')
  static Occasion getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Occasion>(create);
  static Occasion? _defaultInstance;

  /// ID of the parent [`Event`](#rellm-Event) (i.e. the parent `Event.post.id`).
  @$pb.TagNumber(2)
  $core.String get eventId => $_getSZ(0);
  @$pb.TagNumber(2)
  set eventId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(2)
  void clearEventId() => clearField(2);

  /// Optional [`Post`](#rellm-Post) containing alternate title/link/description for this particular Occasion. Its [`PostContext`](#rellm-PostContext) should be `OCCASION`.
  /// An `Occasion`'s ID *is* its `post.id` - there is no separate surrogate ID.
  @$pb.TagNumber(3)
  $8.Post get post => $_getN(1);
  @$pb.TagNumber(3)
  set post($8.Post v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPost() => $_has(1);
  @$pb.TagNumber(3)
  void clearPost() => clearField(3);
  @$pb.TagNumber(3)
  $8.Post ensurePost() => $_ensure(1);

  /// Additional configuration for this [`Occasion`](#rellm-Occasion) beyond the [`EventInfo`](#rellm-EventInfo) in its parent [`Event`](#rellm-Event).
  @$pb.TagNumber(4)
  OccasionInfo get info => $_getN(2);
  @$pb.TagNumber(4)
  set info(OccasionInfo v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasInfo() => $_has(2);
  @$pb.TagNumber(4)
  void clearInfo() => clearField(4);
  @$pb.TagNumber(4)
  OccasionInfo ensureInfo() => $_ensure(2);

  /// The time the event starts (UTC/Timestamp format).
  @$pb.TagNumber(5)
  $13.Timestamp get startsAt => $_getN(3);
  @$pb.TagNumber(5)
  set startsAt($13.Timestamp v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasStartsAt() => $_has(3);
  @$pb.TagNumber(5)
  void clearStartsAt() => clearField(5);
  @$pb.TagNumber(5)
  $13.Timestamp ensureStartsAt() => $_ensure(3);

  /// The time the event ends (UTC/Timestamp format).
  @$pb.TagNumber(6)
  $13.Timestamp get endsAt => $_getN(4);
  @$pb.TagNumber(6)
  set endsAt($13.Timestamp v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasEndsAt() => $_has(4);
  @$pb.TagNumber(6)
  void clearEndsAt() => clearField(6);
  @$pb.TagNumber(6)
  $13.Timestamp ensureEndsAt() => $_ensure(4);

  /// The location of the event.
  @$pb.TagNumber(7)
  $16.Location get location => $_getN(5);
  @$pb.TagNumber(7)
  set location($16.Location v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasLocation() => $_has(5);
  @$pb.TagNumber(7)
  void clearLocation() => clearField(7);
  @$pb.TagNumber(7)
  $16.Location ensureLocation() => $_ensure(5);

  /// The time since this event "disappeared" from the sync source.
  /// It is up to the owner whether this means it should be deleted.
  @$pb.TagNumber(9)
  $13.Timestamp get syncMissingSince => $_getN(6);
  @$pb.TagNumber(9)
  set syncMissingSince($13.Timestamp v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasSyncMissingSince() => $_has(6);
  @$pb.TagNumber(9)
  void clearSyncMissingSince() => clearField(9);
  @$pb.TagNumber(9)
  $13.Timestamp ensureSyncMissingSince() => $_ensure(6);

  /// RSVP + invite data for this Occasion.
  @$pb.TagNumber(10)
  EventAttendances get attendances => $_getN(7);
  @$pb.TagNumber(10)
  set attendances(EventAttendances v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasAttendances() => $_has(7);
  @$pb.TagNumber(10)
  void clearAttendances() => clearField(10);
  @$pb.TagNumber(10)
  EventAttendances ensureAttendances() => $_ensure(7);

  /// If the request was made by a logged-in user, this is the current user's attendance for this Occasion.
  @$pb.TagNumber(11)
  EventAttendance get currentUserAttendance => $_getN(8);
  @$pb.TagNumber(11)
  set currentUserAttendance(EventAttendance v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasCurrentUserAttendance() => $_has(8);
  @$pb.TagNumber(11)
  void clearCurrentUserAttendance() => clearField(11);
  @$pb.TagNumber(11)
  EventAttendance ensureCurrentUserAttendance() => $_ensure(8);

  /// SyncDestinations this Occasion has been synced (cross-posted) to, and their status.
  @$pb.TagNumber(12)
  $core.List<$10.SyncDestinationStatus> get syncDestinations => $_getList(9);

  /// A time zone for the Occasion. Used when serializing it for,
  /// e.g., Facebook or Instagram posts, or generating media.
  @$pb.TagNumber(13)
  $core.String get timezone => $_getSZ(10);
  @$pb.TagNumber(13)
  set timezone($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(13)
  $core.bool hasTimezone() => $_has(10);
  @$pb.TagNumber(13)
  void clearTimezone() => clearField(13);
}

/// To be used for ticketing, RSVPs, etc.
/// Stored as JSON in the database.
class OccasionInfo extends $pb.GeneratedMessage {
  factory OccasionInfo({
    OccasionRsvpInfo? rsvpInfo,
  }) {
    final $result = create();
    if (rsvpInfo != null) {
      $result.rsvpInfo = rsvpInfo;
    }
    return $result;
  }
  OccasionInfo._() : super();
  factory OccasionInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OccasionInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OccasionInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<OccasionRsvpInfo>(1, _omitFieldNames ? '' : 'rsvpInfo', subBuilder: OccasionRsvpInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OccasionInfo clone() => OccasionInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OccasionInfo copyWith(void Function(OccasionInfo) updates) => super.copyWith((message) => updates(message as OccasionInfo)) as OccasionInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OccasionInfo create() => OccasionInfo._();
  OccasionInfo createEmptyInstance() => create();
  static $pb.PbList<OccasionInfo> createRepeated() => $pb.PbList<OccasionInfo>();
  @$core.pragma('dart2js:noInline')
  static OccasionInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OccasionInfo>(create);
  static OccasionInfo? _defaultInstance;

  /// RSVP configuration and metadata for the Occasion.
  @$pb.TagNumber(1)
  OccasionRsvpInfo get rsvpInfo => $_getN(0);
  @$pb.TagNumber(1)
  set rsvpInfo(OccasionRsvpInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRsvpInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearRsvpInfo() => clearField(1);
  @$pb.TagNumber(1)
  OccasionRsvpInfo ensureRsvpInfo() => $_ensure(0);
}

/// Consolidated type for RSVP info for an [`Occasion`](#rellm-Occasion).
/// Curently, the `optional` counts below are *never* returned by the API.
class OccasionRsvpInfo extends $pb.GeneratedMessage {
  factory OccasionRsvpInfo({
    $core.bool? allowsRsvps,
    $core.bool? allowsAnonymousRsvps,
    $core.int? maxAttendees,
    $core.int? goingRsvps,
    $core.int? goingAttendees,
    $core.int? interestedRsvps,
    $core.int? interestedAttendees,
    $core.int? invitedRsvps,
    $core.int? invitedAttendees,
  }) {
    final $result = create();
    if (allowsRsvps != null) {
      $result.allowsRsvps = allowsRsvps;
    }
    if (allowsAnonymousRsvps != null) {
      $result.allowsAnonymousRsvps = allowsAnonymousRsvps;
    }
    if (maxAttendees != null) {
      $result.maxAttendees = maxAttendees;
    }
    if (goingRsvps != null) {
      $result.goingRsvps = goingRsvps;
    }
    if (goingAttendees != null) {
      $result.goingAttendees = goingAttendees;
    }
    if (interestedRsvps != null) {
      $result.interestedRsvps = interestedRsvps;
    }
    if (interestedAttendees != null) {
      $result.interestedAttendees = interestedAttendees;
    }
    if (invitedRsvps != null) {
      $result.invitedRsvps = invitedRsvps;
    }
    if (invitedAttendees != null) {
      $result.invitedAttendees = invitedAttendees;
    }
    return $result;
  }
  OccasionRsvpInfo._() : super();
  factory OccasionRsvpInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OccasionRsvpInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OccasionRsvpInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'allowsRsvps')
    ..aOB(2, _omitFieldNames ? '' : 'allowsAnonymousRsvps')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxAttendees', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'goingRsvps', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'goingAttendees', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'interestedRsvps', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'interestedAttendees', $pb.PbFieldType.OU3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'invitedRsvps', $pb.PbFieldType.OU3)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'invitedAttendees', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OccasionRsvpInfo clone() => OccasionRsvpInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OccasionRsvpInfo copyWith(void Function(OccasionRsvpInfo) updates) => super.copyWith((message) => updates(message as OccasionRsvpInfo)) as OccasionRsvpInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OccasionRsvpInfo create() => OccasionRsvpInfo._();
  OccasionRsvpInfo createEmptyInstance() => create();
  static $pb.PbList<OccasionRsvpInfo> createRepeated() => $pb.PbList<OccasionRsvpInfo>();
  @$core.pragma('dart2js:noInline')
  static OccasionRsvpInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OccasionRsvpInfo>(create);
  static OccasionRsvpInfo? _defaultInstance;

  /// Overrides `EventInfo.allows_rsvps`, if set, for this Occasion.
  @$pb.TagNumber(1)
  $core.bool get allowsRsvps => $_getBF(0);
  @$pb.TagNumber(1)
  set allowsRsvps($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllowsRsvps() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllowsRsvps() => clearField(1);

  /// Overrides `EventInfo.allows_anonymous_rsvps`, if set, for this Occasion.
  @$pb.TagNumber(2)
  $core.bool get allowsAnonymousRsvps => $_getBF(1);
  @$pb.TagNumber(2)
  set allowsAnonymousRsvps($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAllowsAnonymousRsvps() => $_has(1);
  @$pb.TagNumber(2)
  void clearAllowsAnonymousRsvps() => clearField(2);

  /// Overrides `EventInfo.max_attendees`, if set, for this Occasion. Not yet supported.
  @$pb.TagNumber(3)
  $core.int get maxAttendees => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxAttendees($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxAttendees() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxAttendees() => clearField(3);

  /// The number of users who have RSVP'd to the event.
  @$pb.TagNumber(4)
  $core.int get goingRsvps => $_getIZ(3);
  @$pb.TagNumber(4)
  set goingRsvps($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasGoingRsvps() => $_has(3);
  @$pb.TagNumber(4)
  void clearGoingRsvps() => clearField(4);

  /// The number of attendees who have RSVP'd to the event. (RSVPs may have multiple attendees, i.e. guests.)
  @$pb.TagNumber(5)
  $core.int get goingAttendees => $_getIZ(4);
  @$pb.TagNumber(5)
  set goingAttendees($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasGoingAttendees() => $_has(4);
  @$pb.TagNumber(5)
  void clearGoingAttendees() => clearField(5);

  /// The number of users who have signaled interest in the event.
  @$pb.TagNumber(6)
  $core.int get interestedRsvps => $_getIZ(5);
  @$pb.TagNumber(6)
  set interestedRsvps($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasInterestedRsvps() => $_has(5);
  @$pb.TagNumber(6)
  void clearInterestedRsvps() => clearField(6);

  /// The number of attendees who have signaled interest in the event. (RSVPs may have multiple attendees, i.e. guests.)
  @$pb.TagNumber(7)
  $core.int get interestedAttendees => $_getIZ(6);
  @$pb.TagNumber(7)
  set interestedAttendees($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasInterestedAttendees() => $_has(6);
  @$pb.TagNumber(7)
  void clearInterestedAttendees() => clearField(7);

  /// The number of users who have been invited to the event.
  @$pb.TagNumber(8)
  $core.int get invitedRsvps => $_getIZ(7);
  @$pb.TagNumber(8)
  set invitedRsvps($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasInvitedRsvps() => $_has(7);
  @$pb.TagNumber(8)
  void clearInvitedRsvps() => clearField(8);

  /// The number of attendees who have been invited to the event. (RSVPs may have multiple attendees, i.e. guests.)
  @$pb.TagNumber(9)
  $core.int get invitedAttendees => $_getIZ(8);
  @$pb.TagNumber(9)
  set invitedAttendees($core.int v) { $_setUnsignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasInvitedAttendees() => $_has(8);
  @$pb.TagNumber(9)
  void clearInvitedAttendees() => clearField(9);
}

/// Request to get RSVP data for an event.
class GetEventAttendancesRequest extends $pb.GeneratedMessage {
  factory GetEventAttendancesRequest({
    $core.String? occasionId,
    $core.String? anonymousAttendeeAuthToken,
  }) {
    final $result = create();
    if (occasionId != null) {
      $result.occasionId = occasionId;
    }
    if (anonymousAttendeeAuthToken != null) {
      $result.anonymousAttendeeAuthToken = anonymousAttendeeAuthToken;
    }
    return $result;
  }
  GetEventAttendancesRequest._() : super();
  factory GetEventAttendancesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetEventAttendancesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetEventAttendancesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'occasionId')
    ..aOS(2, _omitFieldNames ? '' : 'anonymousAttendeeAuthToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetEventAttendancesRequest clone() => GetEventAttendancesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetEventAttendancesRequest copyWith(void Function(GetEventAttendancesRequest) updates) => super.copyWith((message) => updates(message as GetEventAttendancesRequest)) as GetEventAttendancesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetEventAttendancesRequest create() => GetEventAttendancesRequest._();
  GetEventAttendancesRequest createEmptyInstance() => create();
  static $pb.PbList<GetEventAttendancesRequest> createRepeated() => $pb.PbList<GetEventAttendancesRequest>();
  @$core.pragma('dart2js:noInline')
  static GetEventAttendancesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetEventAttendancesRequest>(create);
  static GetEventAttendancesRequest? _defaultInstance;

  /// The ID of the event to get RSVP data for.
  @$pb.TagNumber(1)
  $core.String get occasionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set occasionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOccasionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOccasionId() => clearField(1);

  /// If set, and if the token has an RSVP for this even, request that RSVP data
  /// in addition to the rest of the RSVP data. (The event creator can always
  /// see and moderate anonymous RSVPs.)
  @$pb.TagNumber(2)
  $core.String get anonymousAttendeeAuthToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set anonymousAttendeeAuthToken($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAnonymousAttendeeAuthToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearAnonymousAttendeeAuthToken() => clearField(2);
}

/// Response to get RSVP data for an event.
class EventAttendances extends $pb.GeneratedMessage {
  factory EventAttendances({
    $core.Iterable<EventAttendance>? attendances,
    $16.Location? hiddenLocation,
  }) {
    final $result = create();
    if (attendances != null) {
      $result.attendances.addAll(attendances);
    }
    if (hiddenLocation != null) {
      $result.hiddenLocation = hiddenLocation;
    }
    return $result;
  }
  EventAttendances._() : super();
  factory EventAttendances.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EventAttendances.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EventAttendances', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<EventAttendance>(1, _omitFieldNames ? '' : 'attendances', $pb.PbFieldType.PM, subBuilder: EventAttendance.create)
    ..aOM<$16.Location>(2, _omitFieldNames ? '' : 'hiddenLocation', subBuilder: $16.Location.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EventAttendances clone() => EventAttendances()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EventAttendances copyWith(void Function(EventAttendances) updates) => super.copyWith((message) => updates(message as EventAttendances)) as EventAttendances;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventAttendances create() => EventAttendances._();
  EventAttendances createEmptyInstance() => create();
  static $pb.PbList<EventAttendances> createRepeated() => $pb.PbList<EventAttendances>();
  @$core.pragma('dart2js:noInline')
  static EventAttendances getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EventAttendances>(create);
  static EventAttendances? _defaultInstance;

  /// The attendance data for the event, in no particular order.
  @$pb.TagNumber(1)
  $core.List<EventAttendance> get attendances => $_getList(0);

  /// When `hide_location_until_rsvp_approved` is set, the location of the event.
  @$pb.TagNumber(2)
  $16.Location get hiddenLocation => $_getN(1);
  @$pb.TagNumber(2)
  set hiddenLocation($16.Location v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasHiddenLocation() => $_has(1);
  @$pb.TagNumber(2)
  void clearHiddenLocation() => clearField(2);
  @$pb.TagNumber(2)
  $16.Location ensureHiddenLocation() => $_ensure(1);
}

enum EventAttendance_Attendee {
  userAttendee, 
  anonymousAttendee, 
  notSet
}

/// Could be called an "RSVP." Describes the attendance of a user at an [`Occasion`](#rellm-Occasion). Such as:
/// * A user's RSVP to an [`Occasion`](#rellm-Occasion) (one of `INTERESTED`, `GOING`, `NOT_GOING`, or , `REQUESTED` (i.e. invited)).
/// * Invitation status of a user to an [`Occasion`](#rellm-Occasion).
/// * [`ContactMethod`](#rellm-ContactMethod)-driven management for anonymous RSVPs to an [`Occasion`](#rellm-Occasion).
class EventAttendance extends $pb.GeneratedMessage {
  factory EventAttendance({
    $core.String? id,
    $core.String? occasionId,
    UserAttendee? userAttendee,
    AnonymousAttendee? anonymousAttendee,
    $core.int? numberOfGuests,
    AttendanceStatus? status,
    $core.String? invitingUserId,
    $core.String? privateNote,
    $core.String? publicNote,
    $14.Moderation? moderation,
    $13.Timestamp? createdAt,
    $13.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (occasionId != null) {
      $result.occasionId = occasionId;
    }
    if (userAttendee != null) {
      $result.userAttendee = userAttendee;
    }
    if (anonymousAttendee != null) {
      $result.anonymousAttendee = anonymousAttendee;
    }
    if (numberOfGuests != null) {
      $result.numberOfGuests = numberOfGuests;
    }
    if (status != null) {
      $result.status = status;
    }
    if (invitingUserId != null) {
      $result.invitingUserId = invitingUserId;
    }
    if (privateNote != null) {
      $result.privateNote = privateNote;
    }
    if (publicNote != null) {
      $result.publicNote = publicNote;
    }
    if (moderation != null) {
      $result.moderation = moderation;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  EventAttendance._() : super();
  factory EventAttendance.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EventAttendance.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, EventAttendance_Attendee> _EventAttendance_AttendeeByTag = {
    3 : EventAttendance_Attendee.userAttendee,
    4 : EventAttendance_Attendee.anonymousAttendee,
    0 : EventAttendance_Attendee.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EventAttendance', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'occasionId')
    ..aOM<UserAttendee>(3, _omitFieldNames ? '' : 'userAttendee', subBuilder: UserAttendee.create)
    ..aOM<AnonymousAttendee>(4, _omitFieldNames ? '' : 'anonymousAttendee', subBuilder: AnonymousAttendee.create)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'numberOfGuests', $pb.PbFieldType.OU3)
    ..e<AttendanceStatus>(6, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE, defaultOrMaker: AttendanceStatus.INTERESTED, valueOf: AttendanceStatus.valueOf, enumValues: AttendanceStatus.values)
    ..aOS(7, _omitFieldNames ? '' : 'invitingUserId')
    ..aOS(8, _omitFieldNames ? '' : 'privateNote')
    ..aOS(9, _omitFieldNames ? '' : 'publicNote')
    ..e<$14.Moderation>(10, _omitFieldNames ? '' : 'moderation', $pb.PbFieldType.OE, defaultOrMaker: $14.Moderation.MODERATION_UNKNOWN, valueOf: $14.Moderation.valueOf, enumValues: $14.Moderation.values)
    ..aOM<$13.Timestamp>(11, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(12, _omitFieldNames ? '' : 'updatedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EventAttendance clone() => EventAttendance()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EventAttendance copyWith(void Function(EventAttendance) updates) => super.copyWith((message) => updates(message as EventAttendance)) as EventAttendance;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventAttendance create() => EventAttendance._();
  EventAttendance createEmptyInstance() => create();
  static $pb.PbList<EventAttendance> createRepeated() => $pb.PbList<EventAttendance>();
  @$core.pragma('dart2js:noInline')
  static EventAttendance getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EventAttendance>(create);
  static EventAttendance? _defaultInstance;

  EventAttendance_Attendee whichAttendee() => _EventAttendance_AttendeeByTag[$_whichOneof(0)]!;
  void clearAttendee() => clearField($_whichOneof(0));

  /// Unique server-generated ID for the attendance.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// ID of the [`Occasion`](#rellm-Occasion) the attendance is for.
  @$pb.TagNumber(2)
  $core.String get occasionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set occasionId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOccasionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOccasionId() => clearField(2);

  /// If the attendance is non-anonymous, core data about the user.
  @$pb.TagNumber(3)
  UserAttendee get userAttendee => $_getN(2);
  @$pb.TagNumber(3)
  set userAttendee(UserAttendee v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserAttendee() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserAttendee() => clearField(3);
  @$pb.TagNumber(3)
  UserAttendee ensureUserAttendee() => $_ensure(2);

  /// If the attendance is anonymous, core data about the anonymous attendee.
  @$pb.TagNumber(4)
  AnonymousAttendee get anonymousAttendee => $_getN(3);
  @$pb.TagNumber(4)
  set anonymousAttendee(AnonymousAttendee v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasAnonymousAttendee() => $_has(3);
  @$pb.TagNumber(4)
  void clearAnonymousAttendee() => clearField(4);
  @$pb.TagNumber(4)
  AnonymousAttendee ensureAnonymousAttendee() => $_ensure(3);

  /// Number of guests including the RSVPing user. (Minimum 1).
  @$pb.TagNumber(5)
  $core.int get numberOfGuests => $_getIZ(4);
  @$pb.TagNumber(5)
  set numberOfGuests($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNumberOfGuests() => $_has(4);
  @$pb.TagNumber(5)
  void clearNumberOfGuests() => clearField(5);

  /// The user's RSVP to an [`Occasion`](#rellm-Occasion) (one of `INTERESTED`, `REQUESTED` (i.e. invited), `GOING`, `NOT_GOING`)
  @$pb.TagNumber(6)
  AttendanceStatus get status => $_getN(5);
  @$pb.TagNumber(6)
  set status(AttendanceStatus v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => clearField(6);

  /// User who invited the attendee. (Not yet used.)
  @$pb.TagNumber(7)
  $core.String get invitingUserId => $_getSZ(6);
  @$pb.TagNumber(7)
  set invitingUserId($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasInvitingUserId() => $_has(6);
  @$pb.TagNumber(7)
  void clearInvitingUserId() => clearField(7);

  /// Public note for everyone who can see the event to see.
  @$pb.TagNumber(8)
  $core.String get privateNote => $_getSZ(7);
  @$pb.TagNumber(8)
  set privateNote($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasPrivateNote() => $_has(7);
  @$pb.TagNumber(8)
  void clearPrivateNote() => clearField(8);

  /// Private note for the event owner.
  @$pb.TagNumber(9)
  $core.String get publicNote => $_getSZ(8);
  @$pb.TagNumber(9)
  set publicNote($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPublicNote() => $_has(8);
  @$pb.TagNumber(9)
  void clearPublicNote() => clearField(9);

  /// Moderation status for the attendance. Moderated by the [`Event`](#rellm-Event) owner (or [`Occasion`](#rellm-Occasion) owner if applicable).
  @$pb.TagNumber(10)
  $14.Moderation get moderation => $_getN(9);
  @$pb.TagNumber(10)
  set moderation($14.Moderation v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasModeration() => $_has(9);
  @$pb.TagNumber(10)
  void clearModeration() => clearField(10);

  /// The time the attendance was created.
  @$pb.TagNumber(11)
  $13.Timestamp get createdAt => $_getN(10);
  @$pb.TagNumber(11)
  set createdAt($13.Timestamp v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasCreatedAt() => $_has(10);
  @$pb.TagNumber(11)
  void clearCreatedAt() => clearField(11);
  @$pb.TagNumber(11)
  $13.Timestamp ensureCreatedAt() => $_ensure(10);

  /// The time the attendance was last updated.
  @$pb.TagNumber(12)
  $13.Timestamp get updatedAt => $_getN(11);
  @$pb.TagNumber(12)
  set updatedAt($13.Timestamp v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasUpdatedAt() => $_has(11);
  @$pb.TagNumber(12)
  void clearUpdatedAt() => clearField(12);
  @$pb.TagNumber(12)
  $13.Timestamp ensureUpdatedAt() => $_ensure(11);
}

///  An anonymous internet user who has RSVP'd to an [`Occasion`](#rellm-Occasion).
///
///  (TODO:) The visibility on `AnonymousAttendee` [`ContactMethod`](#rellm-ContactMethod)s should support the `LIMITED` visibility, which will
///  make them visible to the event creator.
class AnonymousAttendee extends $pb.GeneratedMessage {
  factory AnonymousAttendee({
    $core.String? name,
    $core.Iterable<$4.ContactMethod>? contactMethods,
    $core.String? authToken,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (contactMethods != null) {
      $result.contactMethods.addAll(contactMethods);
    }
    if (authToken != null) {
      $result.authToken = authToken;
    }
    return $result;
  }
  AnonymousAttendee._() : super();
  factory AnonymousAttendee.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AnonymousAttendee.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AnonymousAttendee', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pc<$4.ContactMethod>(2, _omitFieldNames ? '' : 'contactMethods', $pb.PbFieldType.PM, subBuilder: $4.ContactMethod.create)
    ..aOS(3, _omitFieldNames ? '' : 'authToken')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AnonymousAttendee clone() => AnonymousAttendee()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AnonymousAttendee copyWith(void Function(AnonymousAttendee) updates) => super.copyWith((message) => updates(message as AnonymousAttendee)) as AnonymousAttendee;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AnonymousAttendee create() => AnonymousAttendee._();
  AnonymousAttendee createEmptyInstance() => create();
  static $pb.PbList<AnonymousAttendee> createRepeated() => $pb.PbList<AnonymousAttendee>();
  @$core.pragma('dart2js:noInline')
  static AnonymousAttendee getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AnonymousAttendee>(create);
  static AnonymousAttendee? _defaultInstance;

  /// A name for the anonymous user. For instance, "Bob Gomez" or "The guy on your front porch."
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// Contact methods for anonymous attendees. Currently not linked to Contact methods for users.
  @$pb.TagNumber(2)
  $core.List<$4.ContactMethod> get contactMethods => $_getList(1);

  /// Used to allow anonymous users to RSVP to an event. Generated by the server
  /// when an event attendance is upserted for the first time. Subsequent attendance
  /// upserts, with the same occasion_id and anonymous_attendee.auth_token,
  /// will update existing anonymous attendance records. Invalid auth tokens used during upserts will always create a new [`EventAttendance`](#rellm-EventAttendance).
  @$pb.TagNumber(3)
  $core.String get authToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set authToken($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAuthToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthToken() => clearField(3);
}

/// Wire-identical to [Author](#rellm-Author), but with a different name to avoid confusion.
class UserAttendee extends $pb.GeneratedMessage {
  factory UserAttendee({
    $core.String? userId,
    $core.String? username,
    $5.MediaReference? avatar,
    $core.String? realName,
    $core.Iterable<$15.Permission>? permissions,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (username != null) {
      $result.username = username;
    }
    if (avatar != null) {
      $result.avatar = avatar;
    }
    if (realName != null) {
      $result.realName = realName;
    }
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    return $result;
  }
  UserAttendee._() : super();
  factory UserAttendee.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UserAttendee.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UserAttendee', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOM<$5.MediaReference>(3, _omitFieldNames ? '' : 'avatar', subBuilder: $5.MediaReference.create)
    ..aOS(4, _omitFieldNames ? '' : 'realName')
    ..pc<$15.Permission>(5, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UserAttendee clone() => UserAttendee()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UserAttendee copyWith(void Function(UserAttendee) updates) => super.copyWith((message) => updates(message as UserAttendee)) as UserAttendee;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UserAttendee create() => UserAttendee._();
  UserAttendee createEmptyInstance() => create();
  static $pb.PbList<UserAttendee> createRepeated() => $pb.PbList<UserAttendee>();
  @$core.pragma('dart2js:noInline')
  static UserAttendee getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserAttendee>(create);
  static UserAttendee? _defaultInstance;

  /// The user ID of the attendee.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The username of the attendee.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// The attendee's user avatar.
  @$pb.TagNumber(3)
  $5.MediaReference get avatar => $_getN(2);
  @$pb.TagNumber(3)
  set avatar($5.MediaReference v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasAvatar() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvatar() => clearField(3);
  @$pb.TagNumber(3)
  $5.MediaReference ensureAvatar() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get realName => $_getSZ(3);
  @$pb.TagNumber(4)
  set realName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRealName() => $_has(3);
  @$pb.TagNumber(4)
  void clearRealName() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$15.Permission> get permissions => $_getList(4);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
