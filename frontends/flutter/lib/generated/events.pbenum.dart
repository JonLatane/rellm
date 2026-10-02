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

///  The listing type, e.g. `ALL_ACCESSIBLE_EVENTS`, `FOLLOWING_EVENTS`, `MY_GROUPS_EVENTS`, `DIRECT_EVENTS`, `GROUP_EVENTS`, `GROUP_EVENTS_PENDING_MODERATION`.
///
///  Events returned are ordered by start time unless otherwise specified (specifically, `NEWLY_ADDED_EVENTS`).
class EventListingType extends $pb.ProtobufEnum {
  static const EventListingType ALL_ACCESSIBLE_EVENTS = EventListingType._(0, _omitEnumNames ? '' : 'ALL_ACCESSIBLE_EVENTS');
  static const EventListingType FOLLOWING_EVENTS = EventListingType._(1, _omitEnumNames ? '' : 'FOLLOWING_EVENTS');
  static const EventListingType MY_GROUPS_EVENTS = EventListingType._(2, _omitEnumNames ? '' : 'MY_GROUPS_EVENTS');
  static const EventListingType DIRECT_EVENTS = EventListingType._(3, _omitEnumNames ? '' : 'DIRECT_EVENTS');
  static const EventListingType EVENTS_PENDING_MODERATION = EventListingType._(4, _omitEnumNames ? '' : 'EVENTS_PENDING_MODERATION');
  static const EventListingType EVENT_TEXT_SEARCH = EventListingType._(5, _omitEnumNames ? '' : 'EVENT_TEXT_SEARCH');
  static const EventListingType GROUP_EVENTS = EventListingType._(10, _omitEnumNames ? '' : 'GROUP_EVENTS');
  static const EventListingType GROUP_EVENTS_PENDING_MODERATION = EventListingType._(11, _omitEnumNames ? '' : 'GROUP_EVENTS_PENDING_MODERATION');
  static const EventListingType NEWLY_ADDED_EVENTS = EventListingType._(20, _omitEnumNames ? '' : 'NEWLY_ADDED_EVENTS');

  static const $core.List<EventListingType> values = <EventListingType> [
    ALL_ACCESSIBLE_EVENTS,
    FOLLOWING_EVENTS,
    MY_GROUPS_EVENTS,
    DIRECT_EVENTS,
    EVENTS_PENDING_MODERATION,
    EVENT_TEXT_SEARCH,
    GROUP_EVENTS,
    GROUP_EVENTS_PENDING_MODERATION,
    NEWLY_ADDED_EVENTS,
  ];

  static final $core.Map<$core.int, EventListingType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EventListingType? valueOf($core.int value) => _byValue[value];

  const EventListingType._($core.int v, $core.String n) : super(v, n);
}

/// Occasion RSVP statuses. State transitions may generally happen
/// in any direction, but:
/// * `REQUESTED` can only be selected if another user invited the user whose RSVP is being described.
/// * `GOING` and `NOT_GOING` cannot be selected if the Occasion has ended (end time is in the past).
/// * `WENT` and `DID_NOT_GO` cannot be selected if the Occasion has not started (start time is in the future).
/// `INTERESTED` and `REQUESTED` can apply regardless of whether an event has started or ended.
class RsvpStatus extends $pb.ProtobufEnum {
  static const RsvpStatus INTERESTED = RsvpStatus._(0, _omitEnumNames ? '' : 'INTERESTED');
  static const RsvpStatus REQUESTED = RsvpStatus._(1, _omitEnumNames ? '' : 'REQUESTED');
  static const RsvpStatus GOING = RsvpStatus._(2, _omitEnumNames ? '' : 'GOING');
  static const RsvpStatus NOT_GOING = RsvpStatus._(3, _omitEnumNames ? '' : 'NOT_GOING');

  static const $core.List<RsvpStatus> values = <RsvpStatus> [
    INTERESTED,
    REQUESTED,
    GOING,
    NOT_GOING,
  ];

  static final $core.Map<$core.int, RsvpStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static RsvpStatus? valueOf($core.int value) => _byValue[value];

  const RsvpStatus._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
