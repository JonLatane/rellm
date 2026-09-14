//
//  Generated code. Do not modify.
//  source: media.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use mediaConversionDescriptor instead')
const MediaConversion$json = {
  '1': 'MediaConversion',
  '2': [
    {'1': 'MEDIA_CONVERSION_ORIGINAL', '2': 0},
    {'1': 'MEDIA_CONVERSION_SMALL', '2': 1},
    {'1': 'MEDIA_CONVERSION_MEDIUM', '2': 2},
    {'1': 'MEDIA_CONVERSION_LARGE', '2': 3},
    {'1': 'VIDEO_PREVIEW_THUMBNAIL_SMALL', '2': 5},
    {'1': 'VIDEO_PREVIEW_THUMBNAIL_MEDIUM', '2': 6},
    {'1': 'VIDEO_PREVIEW_THUMBNAIL_LARGE', '2': 7},
  ],
};

/// Descriptor for `MediaConversion`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List mediaConversionDescriptor = $convert.base64Decode(
    'Cg9NZWRpYUNvbnZlcnNpb24SHQoZTUVESUFfQ09OVkVSU0lPTl9PUklHSU5BTBAAEhoKFk1FRE'
    'lBX0NPTlZFUlNJT05fU01BTEwQARIbChdNRURJQV9DT05WRVJTSU9OX01FRElVTRACEhoKFk1F'
    'RElBX0NPTlZFUlNJT05fTEFSR0UQAxIhCh1WSURFT19QUkVWSUVXX1RIVU1CTkFJTF9TTUFMTB'
    'AFEiIKHlZJREVPX1BSRVZJRVdfVEhVTUJOQUlMX01FRElVTRAGEiEKHVZJREVPX1BSRVZJRVdf'
    'VEhVTUJOQUlMX0xBUkdFEAc=');

@$core.Deprecated('Use mediaDescriptor instead')
const Media$json = {
  '1': 'Media',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'author', '3': 2, '4': 1, '5': 11, '6': '.rellm.Author', '9': 0, '10': 'author', '17': true},
    {'1': 'name', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'name', '17': true},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'description', '17': true},
    {'1': 'visibility', '3': 6, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'visibility'},
    {'1': 'moderation', '3': 7, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'moderation'},
    {'1': 'generated', '3': 8, '4': 1, '5': 8, '10': 'generated'},
    {'1': 'processed', '3': 9, '4': 1, '5': 8, '10': 'processed'},
    {'1': 'created_at', '3': 15, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 16, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'updatedAt'},
    {'1': 'metadata', '3': 17, '4': 1, '5': 11, '6': '.rellm.MediaMetadata', '10': 'metadata'},
    {'1': 'url', '3': 18, '4': 1, '5': 9, '9': 3, '10': 'url', '17': true},
    {'1': 'sizes', '3': 19, '4': 3, '5': 11, '6': '.rellm.MediaSize', '10': 'sizes'},
  ],
  '8': [
    {'1': '_author'},
    {'1': '_name'},
    {'1': '_description'},
    {'1': '_url'},
  ],
};

/// Descriptor for `Media`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaDescriptor = $convert.base64Decode(
    'CgVNZWRpYRIOCgJpZBgBIAEoCVICaWQSKgoGYXV0aG9yGAIgASgLMg0ucmVsbG0uQXV0aG9ySA'
    'BSBmF1dGhvcogBARIXCgRuYW1lGAQgASgJSAFSBG5hbWWIAQESJQoLZGVzY3JpcHRpb24YBSAB'
    'KAlIAlILZGVzY3JpcHRpb26IAQESMQoKdmlzaWJpbGl0eRgGIAEoDjIRLnJlbGxtLlZpc2liaW'
    'xpdHlSCnZpc2liaWxpdHkSMQoKbW9kZXJhdGlvbhgHIAEoDjIRLnJlbGxtLk1vZGVyYXRpb25S'
    'Cm1vZGVyYXRpb24SHAoJZ2VuZXJhdGVkGAggASgIUglnZW5lcmF0ZWQSHAoJcHJvY2Vzc2VkGA'
    'kgASgIUglwcm9jZXNzZWQSOQoKY3JlYXRlZF9hdBgPIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5U'
    'aW1lc3RhbXBSCWNyZWF0ZWRBdBI5Cgp1cGRhdGVkX2F0GBAgASgLMhouZ29vZ2xlLnByb3RvYn'
    'VmLlRpbWVzdGFtcFIJdXBkYXRlZEF0EjAKCG1ldGFkYXRhGBEgASgLMhQucmVsbG0uTWVkaWFN'
    'ZXRhZGF0YVIIbWV0YWRhdGESFQoDdXJsGBIgASgJSANSA3VybIgBARImCgVzaXplcxgTIAMoCz'
    'IQLnJlbGxtLk1lZGlhU2l6ZVIFc2l6ZXNCCQoHX2F1dGhvckIHCgVfbmFtZUIOCgxfZGVzY3Jp'
    'cHRpb25CBgoEX3VybA==');

@$core.Deprecated('Use mediaSizeDescriptor instead')
const MediaSize$json = {
  '1': 'MediaSize',
  '2': [
    {'1': 'conversion', '3': 1, '4': 1, '5': 14, '6': '.rellm.MediaConversion', '10': 'conversion'},
    {'1': 'size_bytes', '3': 2, '4': 1, '5': 4, '10': 'sizeBytes'},
    {'1': 'aspect_ratio', '3': 3, '4': 1, '5': 2, '9': 0, '10': 'aspectRatio', '17': true},
    {'1': 'content_type', '3': 4, '4': 1, '5': 9, '10': 'contentType'},
  ],
  '8': [
    {'1': '_aspect_ratio'},
  ],
};

/// Descriptor for `MediaSize`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaSizeDescriptor = $convert.base64Decode(
    'CglNZWRpYVNpemUSNgoKY29udmVyc2lvbhgBIAEoDjIWLnJlbGxtLk1lZGlhQ29udmVyc2lvbl'
    'IKY29udmVyc2lvbhIdCgpzaXplX2J5dGVzGAIgASgEUglzaXplQnl0ZXMSJgoMYXNwZWN0X3Jh'
    'dGlvGAMgASgCSABSC2FzcGVjdFJhdGlviAEBEiEKDGNvbnRlbnRfdHlwZRgEIAEoCVILY29udG'
    'VudFR5cGVCDwoNX2FzcGVjdF9yYXRpbw==');

@$core.Deprecated('Use mediaMetadataDescriptor instead')
const MediaMetadata$json = {
  '1': 'MediaMetadata',
  '2': [
    {'1': 'video_preview_time_ms', '3': 1, '4': 1, '5': 4, '9': 0, '10': 'videoPreviewTimeMs', '17': true},
  ],
  '8': [
    {'1': '_video_preview_time_ms'},
  ],
};

/// Descriptor for `MediaMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaMetadataDescriptor = $convert.base64Decode(
    'Cg1NZWRpYU1ldGFkYXRhEjYKFXZpZGVvX3ByZXZpZXdfdGltZV9tcxgBIAEoBEgAUhJ2aWRlb1'
    'ByZXZpZXdUaW1lTXOIAQFCGAoWX3ZpZGVvX3ByZXZpZXdfdGltZV9tcw==');

@$core.Deprecated('Use mediaReferenceDescriptor instead')
const MediaReference$json = {
  '1': 'MediaReference',
  '2': [
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'generated', '3': 4, '4': 1, '5': 8, '10': 'generated'},
    {'1': 'metadata', '3': 5, '4': 1, '5': 11, '6': '.rellm.MediaMetadata', '10': 'metadata'},
    {'1': 'sizes', '3': 6, '4': 3, '5': 11, '6': '.rellm.MediaSize', '10': 'sizes'},
    {'1': 'url', '3': 11, '4': 1, '5': 9, '9': 1, '10': 'url', '17': true},
    {'1': 'description', '3': 12, '4': 1, '5': 9, '9': 2, '10': 'description', '17': true},
    {'1': 'author', '3': 13, '4': 1, '5': 11, '6': '.rellm.Author', '9': 3, '10': 'author', '17': true},
  ],
  '8': [
    {'1': '_name'},
    {'1': '_url'},
    {'1': '_description'},
    {'1': '_author'},
  ],
};

/// Descriptor for `MediaReference`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaReferenceDescriptor = $convert.base64Decode(
    'Cg5NZWRpYVJlZmVyZW5jZRIOCgJpZBgCIAEoCVICaWQSFwoEbmFtZRgDIAEoCUgAUgRuYW1liA'
    'EBEhwKCWdlbmVyYXRlZBgEIAEoCFIJZ2VuZXJhdGVkEjAKCG1ldGFkYXRhGAUgASgLMhQucmVs'
    'bG0uTWVkaWFNZXRhZGF0YVIIbWV0YWRhdGESJgoFc2l6ZXMYBiADKAsyEC5yZWxsbS5NZWRpYV'
    'NpemVSBXNpemVzEhUKA3VybBgLIAEoCUgBUgN1cmyIAQESJQoLZGVzY3JpcHRpb24YDCABKAlI'
    'AlILZGVzY3JpcHRpb26IAQESKgoGYXV0aG9yGA0gASgLMg0ucmVsbG0uQXV0aG9ySANSBmF1dG'
    'hvcogBAUIHCgVfbmFtZUIGCgRfdXJsQg4KDF9kZXNjcmlwdGlvbkIJCgdfYXV0aG9y');

@$core.Deprecated('Use authorDescriptor instead')
const Author$json = {
  '1': 'Author',
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

/// Descriptor for `Author`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authorDescriptor = $convert.base64Decode(
    'CgZBdXRob3ISFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEh8KCHVzZXJuYW1lGAIgASgJSABSCH'
    'VzZXJuYW1liAEBEjIKBmF2YXRhchgDIAEoCzIVLnJlbGxtLk1lZGlhUmVmZXJlbmNlSAFSBmF2'
    'YXRhcogBARIgCglyZWFsX25hbWUYBCABKAlIAlIIcmVhbE5hbWWIAQESMwoLcGVybWlzc2lvbn'
    'MYBSADKA4yES5yZWxsbS5QZXJtaXNzaW9uUgtwZXJtaXNzaW9uc0ILCglfdXNlcm5hbWVCCQoH'
    'X2F2YXRhckIMCgpfcmVhbF9uYW1l');

@$core.Deprecated('Use getMediaRequestDescriptor instead')
const GetMediaRequest$json = {
  '1': 'GetMediaRequest',
  '2': [
    {'1': 'media_id', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'mediaId', '17': true},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'userId', '17': true},
    {'1': 'page', '3': 11, '4': 1, '5': 13, '10': 'page'},
  ],
  '8': [
    {'1': '_media_id'},
    {'1': '_user_id'},
  ],
};

/// Descriptor for `GetMediaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMediaRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRNZWRpYVJlcXVlc3QSHgoIbWVkaWFfaWQYASABKAlIAFIHbWVkaWFJZIgBARIcCgd1c2'
    'VyX2lkGAIgASgJSAFSBnVzZXJJZIgBARISCgRwYWdlGAsgASgNUgRwYWdlQgsKCV9tZWRpYV9p'
    'ZEIKCghfdXNlcl9pZA==');

@$core.Deprecated('Use getMediaResponseDescriptor instead')
const GetMediaResponse$json = {
  '1': 'GetMediaResponse',
  '2': [
    {'1': 'media', '3': 1, '4': 3, '5': 11, '6': '.rellm.Media', '10': 'media'},
    {'1': 'has_next_page', '3': 2, '4': 1, '5': 8, '10': 'hasNextPage'},
  ],
};

/// Descriptor for `GetMediaResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMediaResponseDescriptor = $convert.base64Decode(
    'ChBHZXRNZWRpYVJlc3BvbnNlEiIKBW1lZGlhGAEgAygLMgwucmVsbG0uTWVkaWFSBW1lZGlhEi'
    'IKDWhhc19uZXh0X3BhZ2UYAiABKAhSC2hhc05leHRQYWdl');

