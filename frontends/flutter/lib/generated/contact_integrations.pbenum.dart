//
//  Generated code. Do not modify.
//  source: contact_integrations.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Overall verdict for a provider, domain, or single check. Ordered roughly from best to worst so
/// a UI can pick the "worst" of a list.
class StatusLevel extends $pb.ProtobufEnum {
  static const StatusLevel STATUS_LEVEL_UNKNOWN = StatusLevel._(0, _omitEnumNames ? '' : 'STATUS_LEVEL_UNKNOWN');
  static const StatusLevel STATUS_LEVEL_OK = StatusLevel._(1, _omitEnumNames ? '' : 'STATUS_LEVEL_OK');
  static const StatusLevel STATUS_LEVEL_INFO = StatusLevel._(2, _omitEnumNames ? '' : 'STATUS_LEVEL_INFO');
  static const StatusLevel STATUS_LEVEL_WARNING = StatusLevel._(3, _omitEnumNames ? '' : 'STATUS_LEVEL_WARNING');
  static const StatusLevel STATUS_LEVEL_ERROR = StatusLevel._(4, _omitEnumNames ? '' : 'STATUS_LEVEL_ERROR');
  static const StatusLevel STATUS_LEVEL_DISABLED = StatusLevel._(5, _omitEnumNames ? '' : 'STATUS_LEVEL_DISABLED');

  static const $core.List<StatusLevel> values = <StatusLevel> [
    STATUS_LEVEL_UNKNOWN,
    STATUS_LEVEL_OK,
    STATUS_LEVEL_INFO,
    STATUS_LEVEL_WARNING,
    STATUS_LEVEL_ERROR,
    STATUS_LEVEL_DISABLED,
  ];

  static final $core.Map<$core.int, StatusLevel> _byValue = $pb.ProtobufEnum.initByValue(values);
  static StatusLevel? valueOf($core.int value) => _byValue[value];

  const StatusLevel._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
