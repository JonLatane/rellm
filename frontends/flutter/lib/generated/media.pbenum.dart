//
//  Generated code. Do not modify.
//  source: media.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Which stored copy of a `Media` item's bytes a `MediaSize` represents.
class MediaConversion extends $pb.ProtobufEnum {
  static const MediaConversion MEDIA_CONVERSION_ORIGINAL = MediaConversion._(0, _omitEnumNames ? '' : 'MEDIA_CONVERSION_ORIGINAL');
  static const MediaConversion MEDIA_CONVERSION_SMALL = MediaConversion._(1, _omitEnumNames ? '' : 'MEDIA_CONVERSION_SMALL');
  static const MediaConversion MEDIA_CONVERSION_MEDIUM = MediaConversion._(2, _omitEnumNames ? '' : 'MEDIA_CONVERSION_MEDIUM');
  static const MediaConversion MEDIA_CONVERSION_LARGE = MediaConversion._(3, _omitEnumNames ? '' : 'MEDIA_CONVERSION_LARGE');

  static const $core.List<MediaConversion> values = <MediaConversion> [
    MEDIA_CONVERSION_ORIGINAL,
    MEDIA_CONVERSION_SMALL,
    MEDIA_CONVERSION_MEDIUM,
    MEDIA_CONVERSION_LARGE,
  ];

  static final $core.Map<$core.int, MediaConversion> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MediaConversion? valueOf($core.int value) => _byValue[value];

  const MediaConversion._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
