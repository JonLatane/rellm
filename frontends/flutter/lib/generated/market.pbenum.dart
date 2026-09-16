//
//  Generated code. Do not modify.
//  source: market.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class PurchaseType extends $pb.ProtobufEnum {
  static const PurchaseType PURCHASE_TYPE_MEDIA_STORAGE = PurchaseType._(0, _omitEnumNames ? '' : 'PURCHASE_TYPE_MEDIA_STORAGE');
  static const PurchaseType PURCHASE_TYPE_AI_GRANTS = PurchaseType._(1, _omitEnumNames ? '' : 'PURCHASE_TYPE_AI_GRANTS');
  static const PurchaseType PURCHASE_TYPE_RELLM_HOSTING = PurchaseType._(2, _omitEnumNames ? '' : 'PURCHASE_TYPE_RELLM_HOSTING');
  static const PurchaseType PURCHASE_TYPE_PERMISSIONS_ACCESS = PurchaseType._(3, _omitEnumNames ? '' : 'PURCHASE_TYPE_PERMISSIONS_ACCESS');

  static const $core.List<PurchaseType> values = <PurchaseType> [
    PURCHASE_TYPE_MEDIA_STORAGE,
    PURCHASE_TYPE_AI_GRANTS,
    PURCHASE_TYPE_RELLM_HOSTING,
    PURCHASE_TYPE_PERMISSIONS_ACCESS,
  ];

  static final $core.Map<$core.int, PurchaseType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PurchaseType? valueOf($core.int value) => _byValue[value];

  const PurchaseType._($core.int v, $core.String n) : super(v, n);
}

class PurchasePeriod extends $pb.ProtobufEnum {
  static const PurchasePeriod PURCHASE_PERIOD_INDEFINITE = PurchasePeriod._(0, _omitEnumNames ? '' : 'PURCHASE_PERIOD_INDEFINITE');
  static const PurchasePeriod PURCHASE_PERIOD_ANNUAL = PurchasePeriod._(1, _omitEnumNames ? '' : 'PURCHASE_PERIOD_ANNUAL');
  static const PurchasePeriod PURCHASE_PERIOD_MONTHLY = PurchasePeriod._(2, _omitEnumNames ? '' : 'PURCHASE_PERIOD_MONTHLY');

  static const $core.List<PurchasePeriod> values = <PurchasePeriod> [
    PURCHASE_PERIOD_INDEFINITE,
    PURCHASE_PERIOD_ANNUAL,
    PURCHASE_PERIOD_MONTHLY,
  ];

  static final $core.Map<$core.int, PurchasePeriod> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PurchasePeriod? valueOf($core.int value) => _byValue[value];

  const PurchasePeriod._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
