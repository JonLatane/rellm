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
    {'1': 'AUDIO_PREVIEW_THUMBNAIL_SMALL', '2': 10},
    {'1': 'AUDIO_PREVIEW_THUMBNAIL_MEDIUM', '2': 11},
    {'1': 'AUDIO_PREVIEW_THUMBNAIL_LARGE', '2': 12},
    {'1': 'UNLICENSED_PREVIEW_MEDIUM', '2': 13},
    {'1': 'AUDIO_COVER_ART_SMALL', '2': 15},
    {'1': 'AUDIO_COVER_ART_MEDIUM', '2': 16},
    {'1': 'AUDIO_COVER_ART_LARGE', '2': 17},
  ],
};

/// Descriptor for `MediaConversion`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List mediaConversionDescriptor = $convert.base64Decode(
    'Cg9NZWRpYUNvbnZlcnNpb24SHQoZTUVESUFfQ09OVkVSU0lPTl9PUklHSU5BTBAAEhoKFk1FRE'
    'lBX0NPTlZFUlNJT05fU01BTEwQARIbChdNRURJQV9DT05WRVJTSU9OX01FRElVTRACEhoKFk1F'
    'RElBX0NPTlZFUlNJT05fTEFSR0UQAxIhCh1WSURFT19QUkVWSUVXX1RIVU1CTkFJTF9TTUFMTB'
    'AFEiIKHlZJREVPX1BSRVZJRVdfVEhVTUJOQUlMX01FRElVTRAGEiEKHVZJREVPX1BSRVZJRVdf'
    'VEhVTUJOQUlMX0xBUkdFEAcSIQodQVVESU9fUFJFVklFV19USFVNQk5BSUxfU01BTEwQChIiCh'
    '5BVURJT19QUkVWSUVXX1RIVU1CTkFJTF9NRURJVU0QCxIhCh1BVURJT19QUkVWSUVXX1RIVU1C'
    'TkFJTF9MQVJHRRAMEh0KGVVOTElDRU5TRURfUFJFVklFV19NRURJVU0QDRIZChVBVURJT19DT1'
    'ZFUl9BUlRfU01BTEwQDxIaChZBVURJT19DT1ZFUl9BUlRfTUVESVVNEBASGQoVQVVESU9fQ09W'
    'RVJfQVJUX0xBUkdFEBE=');

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
    {'1': 'artist', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'artist', '17': true},
    {'1': 'album', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'album', '17': true},
    {'1': 'composer', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'composer', '17': true},
    {'1': 'director', '3': 5, '4': 1, '5': 9, '9': 4, '10': 'director', '17': true},
    {'1': 'producer', '3': 6, '4': 1, '5': 9, '9': 5, '10': 'producer', '17': true},
    {'1': 'starring', '3': 7, '4': 1, '5': 9, '9': 6, '10': 'starring', '17': true},
    {'1': 'cast', '3': 8, '4': 1, '5': 9, '9': 7, '10': 'cast', '17': true},
    {'1': 'crew', '3': 9, '4': 1, '5': 9, '9': 8, '10': 'crew', '17': true},
    {'1': 'narrator', '3': 10, '4': 1, '5': 9, '9': 9, '10': 'narrator', '17': true},
    {'1': 'publisher', '3': 11, '4': 1, '5': 9, '9': 10, '10': 'publisher', '17': true},
    {'1': 'unlicensed_preview_start_ms', '3': 12, '4': 1, '5': 4, '9': 11, '10': 'unlicensedPreviewStartMs', '17': true},
    {'1': 'unlicensed_preview_end_ms', '3': 13, '4': 1, '5': 4, '9': 12, '10': 'unlicensedPreviewEndMs', '17': true},
    {'1': 'cover_art_media_id', '3': 14, '4': 1, '5': 9, '9': 13, '10': 'coverArtMediaId', '17': true},
    {'1': 'start_bpm', '3': 15, '4': 1, '5': 2, '9': 14, '10': 'startBpm', '17': true},
    {'1': 'end_bpm', '3': 16, '4': 1, '5': 2, '9': 15, '10': 'endBpm', '17': true},
    {'1': 'min_bpm', '3': 17, '4': 1, '5': 2, '9': 16, '10': 'minBpm', '17': true},
    {'1': 'max_bpm', '3': 18, '4': 1, '5': 2, '9': 17, '10': 'maxBpm', '17': true},
    {'1': 'start_key', '3': 19, '4': 1, '5': 9, '9': 18, '10': 'startKey', '17': true},
    {'1': 'end_key', '3': 20, '4': 1, '5': 9, '9': 19, '10': 'endKey', '17': true},
  ],
  '8': [
    {'1': '_video_preview_time_ms'},
    {'1': '_artist'},
    {'1': '_album'},
    {'1': '_composer'},
    {'1': '_director'},
    {'1': '_producer'},
    {'1': '_starring'},
    {'1': '_cast'},
    {'1': '_crew'},
    {'1': '_narrator'},
    {'1': '_publisher'},
    {'1': '_unlicensed_preview_start_ms'},
    {'1': '_unlicensed_preview_end_ms'},
    {'1': '_cover_art_media_id'},
    {'1': '_start_bpm'},
    {'1': '_end_bpm'},
    {'1': '_min_bpm'},
    {'1': '_max_bpm'},
    {'1': '_start_key'},
    {'1': '_end_key'},
  ],
};

/// Descriptor for `MediaMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaMetadataDescriptor = $convert.base64Decode(
    'Cg1NZWRpYU1ldGFkYXRhEjYKFXZpZGVvX3ByZXZpZXdfdGltZV9tcxgBIAEoBEgAUhJ2aWRlb1'
    'ByZXZpZXdUaW1lTXOIAQESGwoGYXJ0aXN0GAIgASgJSAFSBmFydGlzdIgBARIZCgVhbGJ1bRgD'
    'IAEoCUgCUgVhbGJ1bYgBARIfCghjb21wb3NlchgEIAEoCUgDUghjb21wb3NlcogBARIfCghkaX'
    'JlY3RvchgFIAEoCUgEUghkaXJlY3RvcogBARIfCghwcm9kdWNlchgGIAEoCUgFUghwcm9kdWNl'
    'cogBARIfCghzdGFycmluZxgHIAEoCUgGUghzdGFycmluZ4gBARIXCgRjYXN0GAggASgJSAdSBG'
    'Nhc3SIAQESFwoEY3JldxgJIAEoCUgIUgRjcmV3iAEBEh8KCG5hcnJhdG9yGAogASgJSAlSCG5h'
    'cnJhdG9yiAEBEiEKCXB1Ymxpc2hlchgLIAEoCUgKUglwdWJsaXNoZXKIAQESQgobdW5saWNlbn'
    'NlZF9wcmV2aWV3X3N0YXJ0X21zGAwgASgESAtSGHVubGljZW5zZWRQcmV2aWV3U3RhcnRNc4gB'
    'ARI+Chl1bmxpY2Vuc2VkX3ByZXZpZXdfZW5kX21zGA0gASgESAxSFnVubGljZW5zZWRQcmV2aW'
    'V3RW5kTXOIAQESMAoSY292ZXJfYXJ0X21lZGlhX2lkGA4gASgJSA1SD2NvdmVyQXJ0TWVkaWFJ'
    'ZIgBARIgCglzdGFydF9icG0YDyABKAJIDlIIc3RhcnRCcG2IAQESHAoHZW5kX2JwbRgQIAEoAk'
    'gPUgZlbmRCcG2IAQESHAoHbWluX2JwbRgRIAEoAkgQUgZtaW5CcG2IAQESHAoHbWF4X2JwbRgS'
    'IAEoAkgRUgZtYXhCcG2IAQESIAoJc3RhcnRfa2V5GBMgASgJSBJSCHN0YXJ0S2V5iAEBEhwKB2'
    'VuZF9rZXkYFCABKAlIE1IGZW5kS2V5iAEBQhgKFl92aWRlb19wcmV2aWV3X3RpbWVfbXNCCQoH'
    'X2FydGlzdEIICgZfYWxidW1CCwoJX2NvbXBvc2VyQgsKCV9kaXJlY3RvckILCglfcHJvZHVjZX'
    'JCCwoJX3N0YXJyaW5nQgcKBV9jYXN0QgcKBV9jcmV3QgsKCV9uYXJyYXRvckIMCgpfcHVibGlz'
    'aGVyQh4KHF91bmxpY2Vuc2VkX3ByZXZpZXdfc3RhcnRfbXNCHAoaX3VubGljZW5zZWRfcHJldm'
    'lld19lbmRfbXNCFQoTX2NvdmVyX2FydF9tZWRpYV9pZEIMCgpfc3RhcnRfYnBtQgoKCF9lbmRf'
    'YnBtQgoKCF9taW5fYnBtQgoKCF9tYXhfYnBtQgwKCl9zdGFydF9rZXlCCgoIX2VuZF9rZXk=');

@$core.Deprecated('Use licenseDescriptor instead')
const License$json = {
  '1': 'License',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'licensed_to', '3': 2, '4': 1, '5': 11, '6': '.rellm.Author', '10': 'licensedTo'},
    {'1': 'media', '3': 3, '4': 1, '5': 11, '6': '.rellm.MediaReference', '10': 'media'},
    {'1': 'created_at', '3': 4, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'revoked_at', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'revokedAt', '17': true},
  ],
  '8': [
    {'1': '_revoked_at'},
  ],
};

/// Descriptor for `License`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List licenseDescriptor = $convert.base64Decode(
    'CgdMaWNlbnNlEg4KAmlkGAEgASgJUgJpZBIuCgtsaWNlbnNlZF90bxgCIAEoCzINLnJlbGxtLk'
    'F1dGhvclIKbGljZW5zZWRUbxIrCgVtZWRpYRgDIAEoCzIVLnJlbGxtLk1lZGlhUmVmZXJlbmNl'
    'UgVtZWRpYRI5CgpjcmVhdGVkX2F0GAQgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcF'
    'IJY3JlYXRlZEF0Ej4KCnJldm9rZWRfYXQYBSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0'
    'YW1wSABSCXJldm9rZWRBdIgBAUINCgtfcmV2b2tlZF9hdA==');

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
    {'1': 'visibility', '3': 14, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'visibility'},
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
    'hvcogBARIxCgp2aXNpYmlsaXR5GA4gASgOMhEucmVsbG0uVmlzaWJpbGl0eVIKdmlzaWJpbGl0'
    'eUIHCgVfbmFtZUIGCgRfdXJsQg4KDF9kZXNjcmlwdGlvbkIJCgdfYXV0aG9y');

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
    {'1': 'content_type', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'contentType', '17': true},
    {'1': 'search_text', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'searchText', '17': true},
    {'1': 'page', '3': 11, '4': 1, '5': 13, '10': 'page'},
  ],
  '8': [
    {'1': '_media_id'},
    {'1': '_user_id'},
    {'1': '_content_type'},
    {'1': '_search_text'},
  ],
};

/// Descriptor for `GetMediaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMediaRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRNZWRpYVJlcXVlc3QSHgoIbWVkaWFfaWQYASABKAlIAFIHbWVkaWFJZIgBARIcCgd1c2'
    'VyX2lkGAIgASgJSAFSBnVzZXJJZIgBARImCgxjb250ZW50X3R5cGUYAyABKAlIAlILY29udGVu'
    'dFR5cGWIAQESJAoLc2VhcmNoX3RleHQYBCABKAlIA1IKc2VhcmNoVGV4dIgBARISCgRwYWdlGA'
    'sgASgNUgRwYWdlQgsKCV9tZWRpYV9pZEIKCghfdXNlcl9pZEIPCg1fY29udGVudF90eXBlQg4K'
    'DF9zZWFyY2hfdGV4dA==');

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

