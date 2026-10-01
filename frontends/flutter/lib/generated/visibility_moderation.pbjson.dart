//
//  Generated code. Do not modify.
//  source: visibility_moderation.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use visibilityDescriptor instead')
const Visibility$json = {
  '1': 'Visibility',
  '2': [
    {'1': 'VISIBILITY_UNKNOWN', '2': 0},
    {'1': 'PRIVATE', '2': 1},
    {'1': 'LIMITED', '2': 2},
    {'1': 'SERVER_PUBLIC', '2': 3},
    {'1': 'GLOBAL_PUBLIC', '2': 4},
    {'1': 'DIRECT', '2': 5},
    {'1': 'LICENSED', '2': 6},
  ],
};

/// Descriptor for `Visibility`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List visibilityDescriptor = $convert.base64Decode(
    'CgpWaXNpYmlsaXR5EhYKElZJU0lCSUxJVFlfVU5LTk9XThAAEgsKB1BSSVZBVEUQARILCgdMSU'
    '1JVEVEEAISEQoNU0VSVkVSX1BVQkxJQxADEhEKDUdMT0JBTF9QVUJMSUMQBBIKCgZESVJFQ1QQ'
    'BRIMCghMSUNFTlNFRBAG');

@$core.Deprecated('Use moderationDescriptor instead')
const Moderation$json = {
  '1': 'Moderation',
  '2': [
    {'1': 'MODERATION_UNKNOWN', '2': 0},
    {'1': 'UNMODERATED', '2': 1},
    {'1': 'PENDING', '2': 2},
    {'1': 'APPROVED', '2': 3},
    {'1': 'REJECTED', '2': 4},
  ],
};

/// Descriptor for `Moderation`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List moderationDescriptor = $convert.base64Decode(
    'CgpNb2RlcmF0aW9uEhYKEk1PREVSQVRJT05fVU5LTk9XThAAEg8KC1VOTU9ERVJBVEVEEAESCw'
    'oHUEVORElORxACEgwKCEFQUFJPVkVEEAMSDAoIUkVKRUNURUQQBA==');

