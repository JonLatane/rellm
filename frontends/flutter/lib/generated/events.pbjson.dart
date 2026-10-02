//
//  Generated code. Do not modify.
//  source: events.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use eventListingTypeDescriptor instead')
const EventListingType$json = {
  '1': 'EventListingType',
  '2': [
    {'1': 'ALL_ACCESSIBLE_EVENTS', '2': 0},
    {'1': 'FOLLOWING_EVENTS', '2': 1},
    {'1': 'MY_GROUPS_EVENTS', '2': 2},
    {'1': 'DIRECT_EVENTS', '2': 3},
    {'1': 'EVENTS_PENDING_MODERATION', '2': 4},
    {'1': 'EVENT_TEXT_SEARCH', '2': 5},
    {'1': 'GROUP_EVENTS', '2': 10},
    {'1': 'GROUP_EVENTS_PENDING_MODERATION', '2': 11},
    {'1': 'NEWLY_ADDED_EVENTS', '2': 20},
  ],
};

/// Descriptor for `EventListingType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventListingTypeDescriptor = $convert.base64Decode(
    'ChBFdmVudExpc3RpbmdUeXBlEhkKFUFMTF9BQ0NFU1NJQkxFX0VWRU5UUxAAEhQKEEZPTExPV0'
    'lOR19FVkVOVFMQARIUChBNWV9HUk9VUFNfRVZFTlRTEAISEQoNRElSRUNUX0VWRU5UUxADEh0K'
    'GUVWRU5UU19QRU5ESU5HX01PREVSQVRJT04QBBIVChFFVkVOVF9URVhUX1NFQVJDSBAFEhAKDE'
    'dST1VQX0VWRU5UUxAKEiMKH0dST1VQX0VWRU5UU19QRU5ESU5HX01PREVSQVRJT04QCxIWChJO'
    'RVdMWV9BRERFRF9FVkVOVFMQFA==');

@$core.Deprecated('Use rsvpStatusDescriptor instead')
const RsvpStatus$json = {
  '1': 'RsvpStatus',
  '2': [
    {'1': 'INTERESTED', '2': 0},
    {'1': 'REQUESTED', '2': 1},
    {'1': 'GOING', '2': 2},
    {'1': 'NOT_GOING', '2': 3},
  ],
};

/// Descriptor for `RsvpStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List rsvpStatusDescriptor = $convert.base64Decode(
    'CgpSc3ZwU3RhdHVzEg4KCklOVEVSRVNURUQQABINCglSRVFVRVNURUQQARIJCgVHT0lORxACEg'
    '0KCU5PVF9HT0lORxAD');

@$core.Deprecated('Use getEventsRequestDescriptor instead')
const GetEventsRequest$json = {
  '1': 'GetEventsRequest',
  '2': [
    {'1': 'author_user_id', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'authorUserId', '17': true},
    {'1': 'group_id', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'groupId', '17': true},
    {'1': 'time_filter', '3': 5, '4': 1, '5': 11, '6': '.rellm.TimeFilter', '9': 2, '10': 'timeFilter', '17': true},
    {'1': 'attendee_id', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'attendeeId', '17': true},
    {'1': 'rsvp_statuses', '3': 7, '4': 3, '5': 14, '6': '.rellm.RsvpStatus', '10': 'rsvpStatuses'},
    {'1': 'post_id', '3': 8, '4': 1, '5': 9, '9': 4, '10': 'postId', '17': true},
    {'1': 'listing_type', '3': 10, '4': 1, '5': 14, '6': '.rellm.EventListingType', '10': 'listingType'},
    {'1': 'search_text', '3': 11, '4': 1, '5': 9, '9': 5, '10': 'searchText', '17': true},
    {'1': 'occasion_post_ids', '3': 12, '4': 3, '5': 9, '10': 'occasionPostIds'},
    {'1': 'anonymous_attendee_auth_token', '3': 13, '4': 1, '5': 9, '9': 6, '10': 'anonymousAttendeeAuthToken', '17': true},
  ],
  '8': [
    {'1': '_author_user_id'},
    {'1': '_group_id'},
    {'1': '_time_filter'},
    {'1': '_attendee_id'},
    {'1': '_post_id'},
    {'1': '_search_text'},
    {'1': '_anonymous_attendee_auth_token'},
  ],
  '9': [
    {'1': 1, '2': 2},
    {'1': 4, '2': 5},
  ],
  '10': ['event_id', 'occasion_id'],
};

/// Descriptor for `GetEventsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getEventsRequestDescriptor = $convert.base64Decode(
    'ChBHZXRFdmVudHNSZXF1ZXN0EikKDmF1dGhvcl91c2VyX2lkGAIgASgJSABSDGF1dGhvclVzZX'
    'JJZIgBARIeCghncm91cF9pZBgDIAEoCUgBUgdncm91cElkiAEBEjcKC3RpbWVfZmlsdGVyGAUg'
    'ASgLMhEucmVsbG0uVGltZUZpbHRlckgCUgp0aW1lRmlsdGVyiAEBEiQKC2F0dGVuZGVlX2lkGA'
    'YgASgJSANSCmF0dGVuZGVlSWSIAQESNgoNcnN2cF9zdGF0dXNlcxgHIAMoDjIRLnJlbGxtLlJz'
    'dnBTdGF0dXNSDHJzdnBTdGF0dXNlcxIcCgdwb3N0X2lkGAggASgJSARSBnBvc3RJZIgBARI6Cg'
    'xsaXN0aW5nX3R5cGUYCiABKA4yFy5yZWxsbS5FdmVudExpc3RpbmdUeXBlUgtsaXN0aW5nVHlw'
    'ZRIkCgtzZWFyY2hfdGV4dBgLIAEoCUgFUgpzZWFyY2hUZXh0iAEBEioKEW9jY2FzaW9uX3Bvc3'
    'RfaWRzGAwgAygJUg9vY2Nhc2lvblBvc3RJZHMSRgodYW5vbnltb3VzX2F0dGVuZGVlX2F1dGhf'
    'dG9rZW4YDSABKAlIBlIaYW5vbnltb3VzQXR0ZW5kZWVBdXRoVG9rZW6IAQFCEQoPX2F1dGhvcl'
    '91c2VyX2lkQgsKCV9ncm91cF9pZEIOCgxfdGltZV9maWx0ZXJCDgoMX2F0dGVuZGVlX2lkQgoK'
    'CF9wb3N0X2lkQg4KDF9zZWFyY2hfdGV4dEIgCh5fYW5vbnltb3VzX2F0dGVuZGVlX2F1dGhfdG'
    '9rZW5KBAgBEAJKBAgEEAVSCGV2ZW50X2lkUgtvY2Nhc2lvbl9pZA==');

@$core.Deprecated('Use timeFilterDescriptor instead')
const TimeFilter$json = {
  '1': 'TimeFilter',
  '2': [
    {'1': 'starts_after', '3': 1, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'startsAfter', '17': true},
    {'1': 'ends_after', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'endsAfter', '17': true},
    {'1': 'starts_before', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 2, '10': 'startsBefore', '17': true},
    {'1': 'ends_before', '3': 4, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 3, '10': 'endsBefore', '17': true},
  ],
  '8': [
    {'1': '_starts_after'},
    {'1': '_ends_after'},
    {'1': '_starts_before'},
    {'1': '_ends_before'},
  ],
};

/// Descriptor for `TimeFilter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timeFilterDescriptor = $convert.base64Decode(
    'CgpUaW1lRmlsdGVyEkIKDHN0YXJ0c19hZnRlchgBIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW'
    '1lc3RhbXBIAFILc3RhcnRzQWZ0ZXKIAQESPgoKZW5kc19hZnRlchgCIAEoCzIaLmdvb2dsZS5w'
    'cm90b2J1Zi5UaW1lc3RhbXBIAVIJZW5kc0FmdGVyiAEBEkQKDXN0YXJ0c19iZWZvcmUYAyABKA'
    'syGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wSAJSDHN0YXJ0c0JlZm9yZYgBARJACgtlbmRz'
    'X2JlZm9yZRgEIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIA1IKZW5kc0JlZm9yZY'
    'gBAUIPCg1fc3RhcnRzX2FmdGVyQg0KC19lbmRzX2FmdGVyQhAKDl9zdGFydHNfYmVmb3JlQg4K'
    'DF9lbmRzX2JlZm9yZQ==');

@$core.Deprecated('Use getEventsResponseDescriptor instead')
const GetEventsResponse$json = {
  '1': 'GetEventsResponse',
  '2': [
    {'1': 'events', '3': 1, '4': 3, '5': 11, '6': '.rellm.Event', '10': 'events'},
  ],
};

/// Descriptor for `GetEventsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getEventsResponseDescriptor = $convert.base64Decode(
    'ChFHZXRFdmVudHNSZXNwb25zZRIkCgZldmVudHMYASADKAsyDC5yZWxsbS5FdmVudFIGZXZlbn'
    'Rz');

@$core.Deprecated('Use eventDescriptor instead')
const Event$json = {
  '1': 'Event',
  '2': [
    {'1': 'post', '3': 2, '4': 1, '5': 11, '6': '.rellm.Post', '10': 'post'},
    {'1': 'info', '3': 3, '4': 1, '5': 11, '6': '.rellm.EventInfo', '10': 'info'},
    {'1': 'occasions', '3': 4, '4': 3, '5': 11, '6': '.rellm.Occasion', '10': 'occasions'},
    {'1': 'occasion_count', '3': 5, '4': 1, '5': 4, '10': 'occasionCount'},
  ],
};

/// Descriptor for `Event`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventDescriptor = $convert.base64Decode(
    'CgVFdmVudBIfCgRwb3N0GAIgASgLMgsucmVsbG0uUG9zdFIEcG9zdBIkCgRpbmZvGAMgASgLMh'
    'AucmVsbG0uRXZlbnRJbmZvUgRpbmZvEi0KCW9jY2FzaW9ucxgEIAMoCzIPLnJlbGxtLk9jY2Fz'
    'aW9uUglvY2Nhc2lvbnMSJQoOb2NjYXNpb25fY291bnQYBSABKARSDW9jY2FzaW9uQ291bnQ=');

@$core.Deprecated('Use syncOccasionRequestDescriptor instead')
const SyncOccasionRequest$json = {
  '1': 'SyncOccasionRequest',
  '2': [
    {'1': 'occasion_id', '3': 1, '4': 1, '5': 9, '10': 'occasionId'},
    {'1': 'sync_destination_id', '3': 2, '4': 1, '5': 9, '10': 'syncDestinationId'},
  ],
};

/// Descriptor for `SyncOccasionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncOccasionRequestDescriptor = $convert.base64Decode(
    'ChNTeW5jT2NjYXNpb25SZXF1ZXN0Eh8KC29jY2FzaW9uX2lkGAEgASgJUgpvY2Nhc2lvbklkEi'
    '4KE3N5bmNfZGVzdGluYXRpb25faWQYAiABKAlSEXN5bmNEZXN0aW5hdGlvbklk');

@$core.Deprecated('Use deleteOccasionSyncDestinationRequestDescriptor instead')
const DeleteOccasionSyncDestinationRequest$json = {
  '1': 'DeleteOccasionSyncDestinationRequest',
  '2': [
    {'1': 'occasion_id', '3': 1, '4': 1, '5': 9, '10': 'occasionId'},
    {'1': 'sync_destination_id', '3': 2, '4': 1, '5': 9, '10': 'syncDestinationId'},
  ],
};

/// Descriptor for `DeleteOccasionSyncDestinationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteOccasionSyncDestinationRequestDescriptor = $convert.base64Decode(
    'CiREZWxldGVPY2Nhc2lvblN5bmNEZXN0aW5hdGlvblJlcXVlc3QSHwoLb2NjYXNpb25faWQYAS'
    'ABKAlSCm9jY2FzaW9uSWQSLgoTc3luY19kZXN0aW5hdGlvbl9pZBgCIAEoCVIRc3luY0Rlc3Rp'
    'bmF0aW9uSWQ=');

@$core.Deprecated('Use eventInfoDescriptor instead')
const EventInfo$json = {
  '1': 'EventInfo',
  '2': [
    {'1': 'allows_rsvps', '3': 1, '4': 1, '5': 8, '9': 0, '10': 'allowsRsvps', '17': true},
    {'1': 'allows_anonymous_rsvps', '3': 2, '4': 1, '5': 8, '9': 1, '10': 'allowsAnonymousRsvps', '17': true},
    {'1': 'max_attendees', '3': 3, '4': 1, '5': 13, '9': 2, '10': 'maxAttendees', '17': true},
    {'1': 'hide_location_until_rsvp_approved', '3': 4, '4': 1, '5': 8, '9': 3, '10': 'hideLocationUntilRsvpApproved', '17': true},
    {'1': 'default_rsvp_moderation', '3': 5, '4': 1, '5': 14, '6': '.rellm.Moderation', '9': 4, '10': 'defaultRsvpModeration', '17': true},
  ],
  '8': [
    {'1': '_allows_rsvps'},
    {'1': '_allows_anonymous_rsvps'},
    {'1': '_max_attendees'},
    {'1': '_hide_location_until_rsvp_approved'},
    {'1': '_default_rsvp_moderation'},
  ],
};

/// Descriptor for `EventInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventInfoDescriptor = $convert.base64Decode(
    'CglFdmVudEluZm8SJgoMYWxsb3dzX3JzdnBzGAEgASgISABSC2FsbG93c1JzdnBziAEBEjkKFm'
    'FsbG93c19hbm9ueW1vdXNfcnN2cHMYAiABKAhIAVIUYWxsb3dzQW5vbnltb3VzUnN2cHOIAQES'
    'KAoNbWF4X2F0dGVuZGVlcxgDIAEoDUgCUgxtYXhBdHRlbmRlZXOIAQESTQohaGlkZV9sb2NhdG'
    'lvbl91bnRpbF9yc3ZwX2FwcHJvdmVkGAQgASgISANSHWhpZGVMb2NhdGlvblVudGlsUnN2cEFw'
    'cHJvdmVkiAEBEk4KF2RlZmF1bHRfcnN2cF9tb2RlcmF0aW9uGAUgASgOMhEucmVsbG0uTW9kZX'
    'JhdGlvbkgEUhVkZWZhdWx0UnN2cE1vZGVyYXRpb26IAQFCDwoNX2FsbG93c19yc3Zwc0IZChdf'
    'YWxsb3dzX2Fub255bW91c19yc3Zwc0IQCg5fbWF4X2F0dGVuZGVlc0IkCiJfaGlkZV9sb2NhdG'
    'lvbl91bnRpbF9yc3ZwX2FwcHJvdmVkQhoKGF9kZWZhdWx0X3JzdnBfbW9kZXJhdGlvbg==');

@$core.Deprecated('Use occasionDescriptor instead')
const Occasion$json = {
  '1': 'Occasion',
  '2': [
    {'1': 'event_id', '3': 2, '4': 1, '5': 9, '10': 'eventId'},
    {'1': 'post', '3': 3, '4': 1, '5': 11, '6': '.rellm.Post', '10': 'post'},
    {'1': 'info', '3': 4, '4': 1, '5': 11, '6': '.rellm.OccasionInfo', '10': 'info'},
    {'1': 'starts_at', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'startsAt'},
    {'1': 'ends_at', '3': 6, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'endsAt'},
    {'1': 'location', '3': 7, '4': 1, '5': 11, '6': '.rellm.Location', '9': 0, '10': 'location', '17': true},
    {'1': 'sync_missing_since', '3': 9, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'syncMissingSince', '17': true},
    {'1': 'rsvps', '3': 10, '4': 1, '5': 11, '6': '.rellm.Rsvps', '9': 2, '10': 'rsvps', '17': true},
    {'1': 'current_user_rsvp', '3': 11, '4': 1, '5': 11, '6': '.rellm.Rsvp', '9': 3, '10': 'currentUserRsvp', '17': true},
    {'1': 'sync_destinations', '3': 12, '4': 3, '5': 11, '6': '.rellm.SyncDestinationStatus', '10': 'syncDestinations'},
    {'1': 'timezone', '3': 13, '4': 1, '5': 9, '9': 4, '10': 'timezone', '17': true},
  ],
  '8': [
    {'1': '_location'},
    {'1': '_sync_missing_since'},
    {'1': '_rsvps'},
    {'1': '_current_user_rsvp'},
    {'1': '_timezone'},
  ],
  '9': [
    {'1': 8, '2': 9},
  ],
  '10': ['sync_source_instance_id'],
};

/// Descriptor for `Occasion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List occasionDescriptor = $convert.base64Decode(
    'CghPY2Nhc2lvbhIZCghldmVudF9pZBgCIAEoCVIHZXZlbnRJZBIfCgRwb3N0GAMgASgLMgsucm'
    'VsbG0uUG9zdFIEcG9zdBInCgRpbmZvGAQgASgLMhMucmVsbG0uT2NjYXNpb25JbmZvUgRpbmZv'
    'EjcKCXN0YXJ0c19hdBgFIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCHN0YXJ0c0'
    'F0EjMKB2VuZHNfYXQYBiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgZlbmRzQXQS'
    'MAoIbG9jYXRpb24YByABKAsyDy5yZWxsbS5Mb2NhdGlvbkgAUghsb2NhdGlvbogBARJNChJzeW'
    '5jX21pc3Npbmdfc2luY2UYCSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wSAFSEHN5'
    'bmNNaXNzaW5nU2luY2WIAQESJwoFcnN2cHMYCiABKAsyDC5yZWxsbS5Sc3Zwc0gCUgVyc3Zwc4'
    'gBARI8ChFjdXJyZW50X3VzZXJfcnN2cBgLIAEoCzILLnJlbGxtLlJzdnBIA1IPY3VycmVudFVz'
    'ZXJSc3ZwiAEBEkkKEXN5bmNfZGVzdGluYXRpb25zGAwgAygLMhwucmVsbG0uU3luY0Rlc3Rpbm'
    'F0aW9uU3RhdHVzUhBzeW5jRGVzdGluYXRpb25zEh8KCHRpbWV6b25lGA0gASgJSARSCHRpbWV6'
    'b25liAEBQgsKCV9sb2NhdGlvbkIVChNfc3luY19taXNzaW5nX3NpbmNlQggKBl9yc3Zwc0IUCh'
    'JfY3VycmVudF91c2VyX3JzdnBCCwoJX3RpbWV6b25lSgQICBAJUhdzeW5jX3NvdXJjZV9pbnN0'
    'YW5jZV9pZA==');

@$core.Deprecated('Use occasionInfoDescriptor instead')
const OccasionInfo$json = {
  '1': 'OccasionInfo',
  '2': [
    {'1': 'rsvp_info', '3': 1, '4': 1, '5': 11, '6': '.rellm.OccasionRsvpInfo', '9': 0, '10': 'rsvpInfo', '17': true},
  ],
  '8': [
    {'1': '_rsvp_info'},
  ],
};

/// Descriptor for `OccasionInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List occasionInfoDescriptor = $convert.base64Decode(
    'CgxPY2Nhc2lvbkluZm8SOQoJcnN2cF9pbmZvGAEgASgLMhcucmVsbG0uT2NjYXNpb25Sc3ZwSW'
    '5mb0gAUghyc3ZwSW5mb4gBAUIMCgpfcnN2cF9pbmZv');

@$core.Deprecated('Use occasionRsvpInfoDescriptor instead')
const OccasionRsvpInfo$json = {
  '1': 'OccasionRsvpInfo',
  '2': [
    {'1': 'allows_rsvps', '3': 1, '4': 1, '5': 8, '9': 0, '10': 'allowsRsvps', '17': true},
    {'1': 'allows_anonymous_rsvps', '3': 2, '4': 1, '5': 8, '9': 1, '10': 'allowsAnonymousRsvps', '17': true},
    {'1': 'max_attendees', '3': 3, '4': 1, '5': 13, '9': 2, '10': 'maxAttendees', '17': true},
    {'1': 'going_rsvps', '3': 4, '4': 1, '5': 13, '9': 3, '10': 'goingRsvps', '17': true},
    {'1': 'going_attendees', '3': 5, '4': 1, '5': 13, '9': 4, '10': 'goingAttendees', '17': true},
    {'1': 'interested_rsvps', '3': 6, '4': 1, '5': 13, '9': 5, '10': 'interestedRsvps', '17': true},
    {'1': 'interested_attendees', '3': 7, '4': 1, '5': 13, '9': 6, '10': 'interestedAttendees', '17': true},
    {'1': 'invited_rsvps', '3': 8, '4': 1, '5': 13, '9': 7, '10': 'invitedRsvps', '17': true},
    {'1': 'invited_attendees', '3': 9, '4': 1, '5': 13, '9': 8, '10': 'invitedAttendees', '17': true},
  ],
  '8': [
    {'1': '_allows_rsvps'},
    {'1': '_allows_anonymous_rsvps'},
    {'1': '_max_attendees'},
    {'1': '_going_rsvps'},
    {'1': '_going_attendees'},
    {'1': '_interested_rsvps'},
    {'1': '_interested_attendees'},
    {'1': '_invited_rsvps'},
    {'1': '_invited_attendees'},
  ],
};

/// Descriptor for `OccasionRsvpInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List occasionRsvpInfoDescriptor = $convert.base64Decode(
    'ChBPY2Nhc2lvblJzdnBJbmZvEiYKDGFsbG93c19yc3ZwcxgBIAEoCEgAUgthbGxvd3NSc3Zwc4'
    'gBARI5ChZhbGxvd3NfYW5vbnltb3VzX3JzdnBzGAIgASgISAFSFGFsbG93c0Fub255bW91c1Jz'
    'dnBziAEBEigKDW1heF9hdHRlbmRlZXMYAyABKA1IAlIMbWF4QXR0ZW5kZWVziAEBEiQKC2dvaW'
    '5nX3JzdnBzGAQgASgNSANSCmdvaW5nUnN2cHOIAQESLAoPZ29pbmdfYXR0ZW5kZWVzGAUgASgN'
    'SARSDmdvaW5nQXR0ZW5kZWVziAEBEi4KEGludGVyZXN0ZWRfcnN2cHMYBiABKA1IBVIPaW50ZX'
    'Jlc3RlZFJzdnBziAEBEjYKFGludGVyZXN0ZWRfYXR0ZW5kZWVzGAcgASgNSAZSE2ludGVyZXN0'
    'ZWRBdHRlbmRlZXOIAQESKAoNaW52aXRlZF9yc3ZwcxgIIAEoDUgHUgxpbnZpdGVkUnN2cHOIAQ'
    'ESMAoRaW52aXRlZF9hdHRlbmRlZXMYCSABKA1ICFIQaW52aXRlZEF0dGVuZGVlc4gBAUIPCg1f'
    'YWxsb3dzX3JzdnBzQhkKF19hbGxvd3NfYW5vbnltb3VzX3JzdnBzQhAKDl9tYXhfYXR0ZW5kZW'
    'VzQg4KDF9nb2luZ19yc3Zwc0ISChBfZ29pbmdfYXR0ZW5kZWVzQhMKEV9pbnRlcmVzdGVkX3Jz'
    'dnBzQhcKFV9pbnRlcmVzdGVkX2F0dGVuZGVlc0IQCg5faW52aXRlZF9yc3Zwc0IUChJfaW52aX'
    'RlZF9hdHRlbmRlZXM=');

@$core.Deprecated('Use getRsvpsRequestDescriptor instead')
const GetRsvpsRequest$json = {
  '1': 'GetRsvpsRequest',
  '2': [
    {'1': 'occasion_id', '3': 1, '4': 1, '5': 9, '10': 'occasionId'},
    {'1': 'anonymous_attendee_auth_token', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'anonymousAttendeeAuthToken', '17': true},
  ],
  '8': [
    {'1': '_anonymous_attendee_auth_token'},
  ],
};

/// Descriptor for `GetRsvpsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getRsvpsRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRSc3Zwc1JlcXVlc3QSHwoLb2NjYXNpb25faWQYASABKAlSCm9jY2FzaW9uSWQSRgodYW'
    '5vbnltb3VzX2F0dGVuZGVlX2F1dGhfdG9rZW4YAiABKAlIAFIaYW5vbnltb3VzQXR0ZW5kZWVB'
    'dXRoVG9rZW6IAQFCIAoeX2Fub255bW91c19hdHRlbmRlZV9hdXRoX3Rva2Vu');

@$core.Deprecated('Use rsvpsDescriptor instead')
const Rsvps$json = {
  '1': 'Rsvps',
  '2': [
    {'1': 'rsvps', '3': 1, '4': 3, '5': 11, '6': '.rellm.Rsvp', '10': 'rsvps'},
    {'1': 'hidden_location', '3': 2, '4': 1, '5': 11, '6': '.rellm.Location', '9': 0, '10': 'hiddenLocation', '17': true},
    {'1': 'going_count', '3': 3, '4': 1, '5': 13, '10': 'goingCount'},
    {'1': 'going_attendees', '3': 4, '4': 1, '5': 13, '10': 'goingAttendees'},
    {'1': 'interested_count', '3': 5, '4': 1, '5': 13, '10': 'interestedCount'},
    {'1': 'interested_attendees', '3': 6, '4': 1, '5': 13, '10': 'interestedAttendees'},
    {'1': 'requested_count', '3': 7, '4': 1, '5': 13, '10': 'requestedCount'},
    {'1': 'requested_attendees', '3': 8, '4': 1, '5': 13, '10': 'requestedAttendees'},
    {'1': 'not_going_count', '3': 9, '4': 1, '5': 13, '10': 'notGoingCount'},
    {'1': 'not_going_attendees', '3': 10, '4': 1, '5': 13, '10': 'notGoingAttendees'},
    {'1': 'pending_count', '3': 11, '4': 1, '5': 13, '10': 'pendingCount'},
    {'1': 'pending_attendees', '3': 12, '4': 1, '5': 13, '10': 'pendingAttendees'},
  ],
  '8': [
    {'1': '_hidden_location'},
  ],
};

/// Descriptor for `Rsvps`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rsvpsDescriptor = $convert.base64Decode(
    'CgVSc3ZwcxIhCgVyc3ZwcxgBIAMoCzILLnJlbGxtLlJzdnBSBXJzdnBzEj0KD2hpZGRlbl9sb2'
    'NhdGlvbhgCIAEoCzIPLnJlbGxtLkxvY2F0aW9uSABSDmhpZGRlbkxvY2F0aW9uiAEBEh8KC2dv'
    'aW5nX2NvdW50GAMgASgNUgpnb2luZ0NvdW50EicKD2dvaW5nX2F0dGVuZGVlcxgEIAEoDVIOZ2'
    '9pbmdBdHRlbmRlZXMSKQoQaW50ZXJlc3RlZF9jb3VudBgFIAEoDVIPaW50ZXJlc3RlZENvdW50'
    'EjEKFGludGVyZXN0ZWRfYXR0ZW5kZWVzGAYgASgNUhNpbnRlcmVzdGVkQXR0ZW5kZWVzEicKD3'
    'JlcXVlc3RlZF9jb3VudBgHIAEoDVIOcmVxdWVzdGVkQ291bnQSLwoTcmVxdWVzdGVkX2F0dGVu'
    'ZGVlcxgIIAEoDVIScmVxdWVzdGVkQXR0ZW5kZWVzEiYKD25vdF9nb2luZ19jb3VudBgJIAEoDV'
    'INbm90R29pbmdDb3VudBIuChNub3RfZ29pbmdfYXR0ZW5kZWVzGAogASgNUhFub3RHb2luZ0F0'
    'dGVuZGVlcxIjCg1wZW5kaW5nX2NvdW50GAsgASgNUgxwZW5kaW5nQ291bnQSKwoRcGVuZGluZ1'
    '9hdHRlbmRlZXMYDCABKA1SEHBlbmRpbmdBdHRlbmRlZXNCEgoQX2hpZGRlbl9sb2NhdGlvbg==');

@$core.Deprecated('Use rsvpDescriptor instead')
const Rsvp$json = {
  '1': 'Rsvp',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'occasion_id', '3': 2, '4': 1, '5': 9, '10': 'occasionId'},
    {'1': 'user_attendee', '3': 3, '4': 1, '5': 11, '6': '.rellm.UserAttendee', '9': 0, '10': 'userAttendee'},
    {'1': 'anonymous_attendee', '3': 4, '4': 1, '5': 11, '6': '.rellm.AnonymousAttendee', '9': 0, '10': 'anonymousAttendee'},
    {'1': 'number_of_guests', '3': 5, '4': 1, '5': 13, '10': 'numberOfGuests'},
    {'1': 'status', '3': 6, '4': 1, '5': 14, '6': '.rellm.RsvpStatus', '10': 'status'},
    {'1': 'inviting_user_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'invitingUserId', '17': true},
    {'1': 'private_note', '3': 8, '4': 1, '5': 9, '10': 'privateNote'},
    {'1': 'public_note', '3': 9, '4': 1, '5': 9, '10': 'publicNote'},
    {'1': 'moderation', '3': 10, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'moderation'},
    {'1': 'created_at', '3': 11, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 12, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 2, '10': 'updatedAt', '17': true},
  ],
  '8': [
    {'1': 'attendee'},
    {'1': '_inviting_user_id'},
    {'1': '_updated_at'},
  ],
};

/// Descriptor for `Rsvp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rsvpDescriptor = $convert.base64Decode(
    'CgRSc3ZwEg4KAmlkGAEgASgJUgJpZBIfCgtvY2Nhc2lvbl9pZBgCIAEoCVIKb2NjYXNpb25JZB'
    'I6Cg11c2VyX2F0dGVuZGVlGAMgASgLMhMucmVsbG0uVXNlckF0dGVuZGVlSABSDHVzZXJBdHRl'
    'bmRlZRJJChJhbm9ueW1vdXNfYXR0ZW5kZWUYBCABKAsyGC5yZWxsbS5Bbm9ueW1vdXNBdHRlbm'
    'RlZUgAUhFhbm9ueW1vdXNBdHRlbmRlZRIoChBudW1iZXJfb2ZfZ3Vlc3RzGAUgASgNUg5udW1i'
    'ZXJPZkd1ZXN0cxIpCgZzdGF0dXMYBiABKA4yES5yZWxsbS5Sc3ZwU3RhdHVzUgZzdGF0dXMSLQ'
    'oQaW52aXRpbmdfdXNlcl9pZBgHIAEoCUgBUg5pbnZpdGluZ1VzZXJJZIgBARIhCgxwcml2YXRl'
    'X25vdGUYCCABKAlSC3ByaXZhdGVOb3RlEh8KC3B1YmxpY19ub3RlGAkgASgJUgpwdWJsaWNOb3'
    'RlEjEKCm1vZGVyYXRpb24YCiABKA4yES5yZWxsbS5Nb2RlcmF0aW9uUgptb2RlcmF0aW9uEjkK'
    'CmNyZWF0ZWRfYXQYCyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVkQX'
    'QSPgoKdXBkYXRlZF9hdBgMIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAlIJdXBk'
    'YXRlZEF0iAEBQgoKCGF0dGVuZGVlQhMKEV9pbnZpdGluZ191c2VyX2lkQg0KC191cGRhdGVkX2'
    'F0');

@$core.Deprecated('Use anonymousAttendeeDescriptor instead')
const AnonymousAttendee$json = {
  '1': 'AnonymousAttendee',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'contact_methods', '3': 2, '4': 3, '5': 11, '6': '.rellm.ContactMethod', '10': 'contactMethods'},
    {'1': 'auth_token', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'authToken', '17': true},
  ],
  '8': [
    {'1': '_auth_token'},
  ],
};

/// Descriptor for `AnonymousAttendee`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List anonymousAttendeeDescriptor = $convert.base64Decode(
    'ChFBbm9ueW1vdXNBdHRlbmRlZRISCgRuYW1lGAEgASgJUgRuYW1lEj0KD2NvbnRhY3RfbWV0aG'
    '9kcxgCIAMoCzIULnJlbGxtLkNvbnRhY3RNZXRob2RSDmNvbnRhY3RNZXRob2RzEiIKCmF1dGhf'
    'dG9rZW4YAyABKAlIAFIJYXV0aFRva2VuiAEBQg0KC19hdXRoX3Rva2Vu');

@$core.Deprecated('Use userAttendeeDescriptor instead')
const UserAttendee$json = {
  '1': 'UserAttendee',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'username', '17': true},
    {'1': 'avatar', '3': 3, '4': 1, '5': 11, '6': '.rellm.MediaReference', '9': 1, '10': 'avatar', '17': true},
    {'1': 'real_name', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'realName', '17': true},
    {'1': 'permissions', '3': 5, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'permissions'},
  ],
  '8': [
    {'1': '_username'},
    {'1': '_avatar'},
    {'1': '_real_name'},
  ],
};

/// Descriptor for `UserAttendee`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userAttendeeDescriptor = $convert.base64Decode(
    'CgxVc2VyQXR0ZW5kZWUSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEh8KCHVzZXJuYW1lGAIgAS'
    'gJSABSCHVzZXJuYW1liAEBEjIKBmF2YXRhchgDIAEoCzIVLnJlbGxtLk1lZGlhUmVmZXJlbmNl'
    'SAFSBmF2YXRhcogBARIgCglyZWFsX25hbWUYBCABKAlIAlIIcmVhbE5hbWWIAQESMwoLcGVybW'
    'lzc2lvbnMYBSADKA4yES5yZWxsbS5QZXJtaXNzaW9uUgtwZXJtaXNzaW9uc0ILCglfdXNlcm5h'
    'bWVCCQoHX2F2YXRhckIMCgpfcmVhbF9uYW1l');

