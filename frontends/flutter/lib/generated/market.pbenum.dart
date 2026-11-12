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

/// What a `MarketProduct`/`MarketPurchase`/`MarketSubscription` actually grants the buyer once
/// fulfilled -- see `logic::market::market_fulfillment::fulfill_purchase` (the Rust match on this same enum)
/// for exactly what each value does. Immutable on a `MarketProduct` once created (see that message's
/// own doc) -- changing what a product *is* after people have already bought it would silently
/// change existing buyers' entitlements out from under them, so a product whose type needs to change
/// is delisted and replaced with a new one instead.
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

/// How often a `MarketProduct`/`MarketSubscription` bills. Immutable on a `MarketProduct` once
/// created (see that message's own doc) -- same reasoning as `PurchaseType`'s immutability.
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

/// The state of a `PURCHASE_TYPE_RELLM_HOSTING` order's manual fulfillment -- see
/// `RellmHostingSubscriptionDetails.fulfillment_status`'s own doc for how the "current" value is
/// derived, and `FulfillmentNote.fulfillment_status` for how every transition is recorded as its own
/// timestamped note (a "fulfillment state history"), not just tracked as a bare current value.
class FulfillmentStatus extends $pb.ProtobufEnum {
  static const FulfillmentStatus FULFILLMENT_STATUS_AWAITING_HOST_ADMIN = FulfillmentStatus._(0, _omitEnumNames ? '' : 'FULFILLMENT_STATUS_AWAITING_HOST_ADMIN');
  static const FulfillmentStatus FULFILLMENT_STATUS_FULFILLED = FulfillmentStatus._(1, _omitEnumNames ? '' : 'FULFILLMENT_STATUS_FULFILLED');
  static const FulfillmentStatus FULFILLMENT_STATUS_IN_PROGRESS = FulfillmentStatus._(2, _omitEnumNames ? '' : 'FULFILLMENT_STATUS_IN_PROGRESS');

  static const $core.List<FulfillmentStatus> values = <FulfillmentStatus> [
    FULFILLMENT_STATUS_AWAITING_HOST_ADMIN,
    FULFILLMENT_STATUS_FULFILLED,
    FULFILLMENT_STATUS_IN_PROGRESS,
  ];

  static final $core.Map<$core.int, FulfillmentStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static FulfillmentStatus? valueOf($core.int value) => _byValue[value];

  const FulfillmentStatus._($core.int v, $core.String n) : super(v, n);
}

class GetMarketSubscriptionsRequestType extends $pb.ProtobufEnum {
  static const GetMarketSubscriptionsRequestType GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE = GetMarketSubscriptionsRequestType._(0, _omitEnumNames ? '' : 'GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE');
  static const GetMarketSubscriptionsRequestType GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN = GetMarketSubscriptionsRequestType._(1, _omitEnumNames ? '' : 'GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN');

  static const $core.List<GetMarketSubscriptionsRequestType> values = <GetMarketSubscriptionsRequestType> [
    GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE,
    GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN,
  ];

  static final $core.Map<$core.int, GetMarketSubscriptionsRequestType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static GetMarketSubscriptionsRequestType? valueOf($core.int value) => _byValue[value];

  const GetMarketSubscriptionsRequestType._($core.int v, $core.String n) : super(v, n);
}

/// Where a `MarketSubscription` stands from the *buyer's* point of view -- always derived on the fly
/// (never stored as a column) from `canceled_at`/`renews_at`/`service_terminated_at` as of the moment
/// the subscription is marshaled, see `logic::market::market_subscription_state`. The point of the
/// middle value: a buyer who cancels has still paid for the rest of their current billing period, so
/// cancellation is not an instant "off switch" -- they keep their entitlement until it runs out, and
/// can resume (see `MakeMarketPurchaseResponse.resumed_subscription`) any time before then without
/// paying again.
class MarketSubscriptionState extends $pb.ProtobufEnum {
  static const MarketSubscriptionState SUBSCRIPTION_ACTIVE = MarketSubscriptionState._(0, _omitEnumNames ? '' : 'SUBSCRIPTION_ACTIVE');
  static const MarketSubscriptionState SUBSCRIPTION_ACTIVE_BUT_CANCELED = MarketSubscriptionState._(1, _omitEnumNames ? '' : 'SUBSCRIPTION_ACTIVE_BUT_CANCELED');
  static const MarketSubscriptionState SUBSCRIPTION_CANCELED = MarketSubscriptionState._(2, _omitEnumNames ? '' : 'SUBSCRIPTION_CANCELED');

  static const $core.List<MarketSubscriptionState> values = <MarketSubscriptionState> [
    SUBSCRIPTION_ACTIVE,
    SUBSCRIPTION_ACTIVE_BUT_CANCELED,
    SUBSCRIPTION_CANCELED,
  ];

  static final $core.Map<$core.int, MarketSubscriptionState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MarketSubscriptionState? valueOf($core.int value) => _byValue[value];

  const MarketSubscriptionState._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
