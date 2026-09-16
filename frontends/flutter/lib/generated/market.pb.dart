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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/timestamp.pb.dart' as $13;
import 'market.pbenum.dart';
import 'media.pb.dart' as $5;

export 'market.pbenum.dart';

enum MarketProduct_Details {
  mediaStorageSubscriptionDetails, 
  aiGrantSubscriptionDetails, 
  rellmHostingSubscriptionDetails, 
  notSet
}

/// An actual subscribable product listed on, say, https://rellm.org/market
/// Listed/delisted by clients by setting `delisted_at` (though the actual date supplied
/// by the client is ignored).
class MarketProduct extends $pb.GeneratedMessage {
  factory MarketProduct({
    $core.String? id,
    PurchaseType? type,
    PurchasePeriod? period,
    $core.int? amount,
    $core.int? currency,
    MediaStorageSubscriptionDetails? mediaStorageSubscriptionDetails,
    AIGrantSubscriptionDetails? aiGrantSubscriptionDetails,
    RellmHostingSubscriptionDetails? rellmHostingSubscriptionDetails,
    $13.Timestamp? createdAt,
    $13.Timestamp? delistedAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (type != null) {
      $result.type = type;
    }
    if (period != null) {
      $result.period = period;
    }
    if (amount != null) {
      $result.amount = amount;
    }
    if (currency != null) {
      $result.currency = currency;
    }
    if (mediaStorageSubscriptionDetails != null) {
      $result.mediaStorageSubscriptionDetails = mediaStorageSubscriptionDetails;
    }
    if (aiGrantSubscriptionDetails != null) {
      $result.aiGrantSubscriptionDetails = aiGrantSubscriptionDetails;
    }
    if (rellmHostingSubscriptionDetails != null) {
      $result.rellmHostingSubscriptionDetails = rellmHostingSubscriptionDetails;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (delistedAt != null) {
      $result.delistedAt = delistedAt;
    }
    return $result;
  }
  MarketProduct._() : super();
  factory MarketProduct.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketProduct.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, MarketProduct_Details> _MarketProduct_DetailsByTag = {
    10 : MarketProduct_Details.mediaStorageSubscriptionDetails,
    11 : MarketProduct_Details.aiGrantSubscriptionDetails,
    12 : MarketProduct_Details.rellmHostingSubscriptionDetails,
    0 : MarketProduct_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketProduct', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..e<PurchaseType>(2, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: PurchaseType.PURCHASE_TYPE_MEDIA_STORAGE, valueOf: PurchaseType.valueOf, enumValues: PurchaseType.values)
    ..e<PurchasePeriod>(3, _omitFieldNames ? '' : 'period', $pb.PbFieldType.OE, defaultOrMaker: PurchasePeriod.PURCHASE_PERIOD_INDEFINITE, valueOf: PurchasePeriod.valueOf, enumValues: PurchasePeriod.values)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'amount', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'currency', $pb.PbFieldType.OU3)
    ..aOM<MediaStorageSubscriptionDetails>(10, _omitFieldNames ? '' : 'mediaStorageSubscriptionDetails', subBuilder: MediaStorageSubscriptionDetails.create)
    ..aOM<AIGrantSubscriptionDetails>(11, _omitFieldNames ? '' : 'aiGrantSubscriptionDetails', subBuilder: AIGrantSubscriptionDetails.create)
    ..aOM<RellmHostingSubscriptionDetails>(12, _omitFieldNames ? '' : 'rellmHostingSubscriptionDetails', subBuilder: RellmHostingSubscriptionDetails.create)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(21, _omitFieldNames ? '' : 'delistedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketProduct clone() => MarketProduct()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketProduct copyWith(void Function(MarketProduct) updates) => super.copyWith((message) => updates(message as MarketProduct)) as MarketProduct;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketProduct create() => MarketProduct._();
  MarketProduct createEmptyInstance() => create();
  static $pb.PbList<MarketProduct> createRepeated() => $pb.PbList<MarketProduct>();
  @$core.pragma('dart2js:noInline')
  static MarketProduct getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketProduct>(create);
  static MarketProduct? _defaultInstance;

  MarketProduct_Details whichDetails() => _MarketProduct_DetailsByTag[$_whichOneof(0)]!;
  void clearDetails() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Never changeable after product creation.
  @$pb.TagNumber(2)
  PurchaseType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(PurchaseType v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  /// Never changeable after product creation.
  @$pb.TagNumber(3)
  PurchasePeriod get period => $_getN(2);
  @$pb.TagNumber(3)
  set period(PurchasePeriod v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPeriod() => $_has(2);
  @$pb.TagNumber(3)
  void clearPeriod() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get amount => $_getIZ(3);
  @$pb.TagNumber(4)
  set amount($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAmount() => $_has(3);
  @$pb.TagNumber(4)
  void clearAmount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get currency => $_getIZ(4);
  @$pb.TagNumber(5)
  set currency($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => clearField(5);

  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails get mediaStorageSubscriptionDetails => $_getN(5);
  @$pb.TagNumber(10)
  set mediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasMediaStorageSubscriptionDetails() => $_has(5);
  @$pb.TagNumber(10)
  void clearMediaStorageSubscriptionDetails() => clearField(10);
  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails ensureMediaStorageSubscriptionDetails() => $_ensure(5);

  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails get aiGrantSubscriptionDetails => $_getN(6);
  @$pb.TagNumber(11)
  set aiGrantSubscriptionDetails(AIGrantSubscriptionDetails v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAiGrantSubscriptionDetails() => $_has(6);
  @$pb.TagNumber(11)
  void clearAiGrantSubscriptionDetails() => clearField(11);
  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails ensureAiGrantSubscriptionDetails() => $_ensure(6);

  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails get rellmHostingSubscriptionDetails => $_getN(7);
  @$pb.TagNumber(12)
  set rellmHostingSubscriptionDetails(RellmHostingSubscriptionDetails v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasRellmHostingSubscriptionDetails() => $_has(7);
  @$pb.TagNumber(12)
  void clearRellmHostingSubscriptionDetails() => clearField(12);
  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails ensureRellmHostingSubscriptionDetails() => $_ensure(7);

  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(8);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(8);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(8);

  /// If set, the MarketProduct is not purchasable. Note: clients toggle listings by setting this,
  /// but the server will always set it to the time of the request, not the time sent *by* the request.
  @$pb.TagNumber(21)
  $13.Timestamp get delistedAt => $_getN(9);
  @$pb.TagNumber(21)
  set delistedAt($13.Timestamp v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasDelistedAt() => $_has(9);
  @$pb.TagNumber(21)
  void clearDelistedAt() => clearField(21);
  @$pb.TagNumber(21)
  $13.Timestamp ensureDelistedAt() => $_ensure(9);
}

/// Request to get products available for purchase on a Rellm server.
/// For now, there are few enough that this has no parameters.
class GetMarketProductsRequest extends $pb.GeneratedMessage {
  factory GetMarketProductsRequest() => create();
  GetMarketProductsRequest._() : super();
  factory GetMarketProductsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMarketProductsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMarketProductsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMarketProductsRequest clone() => GetMarketProductsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMarketProductsRequest copyWith(void Function(GetMarketProductsRequest) updates) => super.copyWith((message) => updates(message as GetMarketProductsRequest)) as GetMarketProductsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMarketProductsRequest create() => GetMarketProductsRequest._();
  GetMarketProductsRequest createEmptyInstance() => create();
  static $pb.PbList<GetMarketProductsRequest> createRepeated() => $pb.PbList<GetMarketProductsRequest>();
  @$core.pragma('dart2js:noInline')
  static GetMarketProductsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMarketProductsRequest>(create);
  static GetMarketProductsRequest? _defaultInstance;
}

class GetMarketProductsResponse extends $pb.GeneratedMessage {
  factory GetMarketProductsResponse({
    $core.Iterable<MarketProduct>? marketProducts,
  }) {
    final $result = create();
    if (marketProducts != null) {
      $result.marketProducts.addAll(marketProducts);
    }
    return $result;
  }
  GetMarketProductsResponse._() : super();
  factory GetMarketProductsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMarketProductsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMarketProductsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<MarketProduct>(1, _omitFieldNames ? '' : 'marketProducts', $pb.PbFieldType.PM, subBuilder: MarketProduct.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMarketProductsResponse clone() => GetMarketProductsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMarketProductsResponse copyWith(void Function(GetMarketProductsResponse) updates) => super.copyWith((message) => updates(message as GetMarketProductsResponse)) as GetMarketProductsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMarketProductsResponse create() => GetMarketProductsResponse._();
  GetMarketProductsResponse createEmptyInstance() => create();
  static $pb.PbList<GetMarketProductsResponse> createRepeated() => $pb.PbList<GetMarketProductsResponse>();
  @$core.pragma('dart2js:noInline')
  static GetMarketProductsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMarketProductsResponse>(create);
  static GetMarketProductsResponse? _defaultInstance;

  /// Non-delisted products, plus delisted ones too if the caller is an admin.
  @$pb.TagNumber(1)
  $core.List<MarketProduct> get marketProducts => $_getList(0);
}

/// Request to get the current user's own MarketSubscriptions (with billing_history). Self-scoped --
/// there's no way to fetch another user's MarketSubscriptions, even as an admin, for now.
class GetMarketSubscriptionsRequest extends $pb.GeneratedMessage {
  factory GetMarketSubscriptionsRequest() => create();
  GetMarketSubscriptionsRequest._() : super();
  factory GetMarketSubscriptionsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMarketSubscriptionsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMarketSubscriptionsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMarketSubscriptionsRequest clone() => GetMarketSubscriptionsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMarketSubscriptionsRequest copyWith(void Function(GetMarketSubscriptionsRequest) updates) => super.copyWith((message) => updates(message as GetMarketSubscriptionsRequest)) as GetMarketSubscriptionsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMarketSubscriptionsRequest create() => GetMarketSubscriptionsRequest._();
  GetMarketSubscriptionsRequest createEmptyInstance() => create();
  static $pb.PbList<GetMarketSubscriptionsRequest> createRepeated() => $pb.PbList<GetMarketSubscriptionsRequest>();
  @$core.pragma('dart2js:noInline')
  static GetMarketSubscriptionsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMarketSubscriptionsRequest>(create);
  static GetMarketSubscriptionsRequest? _defaultInstance;
}

class GetMarketSubscriptionsResponse extends $pb.GeneratedMessage {
  factory GetMarketSubscriptionsResponse({
    $core.Iterable<MarketSubscription>? marketSubscriptions,
  }) {
    final $result = create();
    if (marketSubscriptions != null) {
      $result.marketSubscriptions.addAll(marketSubscriptions);
    }
    return $result;
  }
  GetMarketSubscriptionsResponse._() : super();
  factory GetMarketSubscriptionsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMarketSubscriptionsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMarketSubscriptionsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<MarketSubscription>(1, _omitFieldNames ? '' : 'marketSubscriptions', $pb.PbFieldType.PM, subBuilder: MarketSubscription.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMarketSubscriptionsResponse clone() => GetMarketSubscriptionsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMarketSubscriptionsResponse copyWith(void Function(GetMarketSubscriptionsResponse) updates) => super.copyWith((message) => updates(message as GetMarketSubscriptionsResponse)) as GetMarketSubscriptionsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMarketSubscriptionsResponse create() => GetMarketSubscriptionsResponse._();
  GetMarketSubscriptionsResponse createEmptyInstance() => create();
  static $pb.PbList<GetMarketSubscriptionsResponse> createRepeated() => $pb.PbList<GetMarketSubscriptionsResponse>();
  @$core.pragma('dart2js:noInline')
  static GetMarketSubscriptionsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMarketSubscriptionsResponse>(create);
  static GetMarketSubscriptionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<MarketSubscription> get marketSubscriptions => $_getList(0);
}

/// *Authenticated*. Buys `market_product_id` for the current user, starting (or continuing) a
/// Stripe Checkout flow -- see `MakeMarketPurchaseResponse.checkout_url`. No `MarketPurchase`/
/// `MarketSubscription` is created by this call itself; that only happens once Stripe confirms
/// payment via webhook, so an abandoned checkout never leaves a half-created purchase behind.
class MakeMarketPurchaseRequest extends $pb.GeneratedMessage {
  factory MakeMarketPurchaseRequest({
    $core.String? marketProductId,
    RellmHostingPurchaseDetails? rellmHostingDetails,
  }) {
    final $result = create();
    if (marketProductId != null) {
      $result.marketProductId = marketProductId;
    }
    if (rellmHostingDetails != null) {
      $result.rellmHostingDetails = rellmHostingDetails;
    }
    return $result;
  }
  MakeMarketPurchaseRequest._() : super();
  factory MakeMarketPurchaseRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MakeMarketPurchaseRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MakeMarketPurchaseRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'marketProductId')
    ..aOM<RellmHostingPurchaseDetails>(2, _omitFieldNames ? '' : 'rellmHostingDetails', subBuilder: RellmHostingPurchaseDetails.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MakeMarketPurchaseRequest clone() => MakeMarketPurchaseRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MakeMarketPurchaseRequest copyWith(void Function(MakeMarketPurchaseRequest) updates) => super.copyWith((message) => updates(message as MakeMarketPurchaseRequest)) as MakeMarketPurchaseRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MakeMarketPurchaseRequest create() => MakeMarketPurchaseRequest._();
  MakeMarketPurchaseRequest createEmptyInstance() => create();
  static $pb.PbList<MakeMarketPurchaseRequest> createRepeated() => $pb.PbList<MakeMarketPurchaseRequest>();
  @$core.pragma('dart2js:noInline')
  static MakeMarketPurchaseRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MakeMarketPurchaseRequest>(create);
  static MakeMarketPurchaseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get marketProductId => $_getSZ(0);
  @$pb.TagNumber(1)
  set marketProductId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMarketProductId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMarketProductId() => clearField(1);

  /// Only meaningful (and required) for a `PURCHASE_TYPE_RELLM_HOSTING` product -- the buyer's
  /// desired domain/contact info/notes, carried through to Stripe as Checkout Session metadata and
  /// copied onto the resulting `MarketPurchase`/`MarketSubscription` once payment completes.
  @$pb.TagNumber(2)
  RellmHostingPurchaseDetails get rellmHostingDetails => $_getN(1);
  @$pb.TagNumber(2)
  set rellmHostingDetails(RellmHostingPurchaseDetails v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasRellmHostingDetails() => $_has(1);
  @$pb.TagNumber(2)
  void clearRellmHostingDetails() => clearField(2);
  @$pb.TagNumber(2)
  RellmHostingPurchaseDetails ensureRellmHostingDetails() => $_ensure(1);
}

class MakeMarketPurchaseResponse extends $pb.GeneratedMessage {
  factory MakeMarketPurchaseResponse({
    $core.String? checkoutUrl,
  }) {
    final $result = create();
    if (checkoutUrl != null) {
      $result.checkoutUrl = checkoutUrl;
    }
    return $result;
  }
  MakeMarketPurchaseResponse._() : super();
  factory MakeMarketPurchaseResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MakeMarketPurchaseResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MakeMarketPurchaseResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'checkoutUrl')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MakeMarketPurchaseResponse clone() => MakeMarketPurchaseResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MakeMarketPurchaseResponse copyWith(void Function(MakeMarketPurchaseResponse) updates) => super.copyWith((message) => updates(message as MakeMarketPurchaseResponse)) as MakeMarketPurchaseResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MakeMarketPurchaseResponse create() => MakeMarketPurchaseResponse._();
  MakeMarketPurchaseResponse createEmptyInstance() => create();
  static $pb.PbList<MakeMarketPurchaseResponse> createRepeated() => $pb.PbList<MakeMarketPurchaseResponse>();
  @$core.pragma('dart2js:noInline')
  static MakeMarketPurchaseResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MakeMarketPurchaseResponse>(create);
  static MakeMarketPurchaseResponse? _defaultInstance;

  /// Redirect the buyer's browser here (a Stripe-hosted Checkout page) to complete payment.
  @$pb.TagNumber(1)
  $core.String get checkoutUrl => $_getSZ(0);
  @$pb.TagNumber(1)
  set checkoutUrl($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCheckoutUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearCheckoutUrl() => clearField(1);
}

enum MarketPurchase_Details {
  mediaStoragePurchaseDetails, 
  aiGrantPurchaseDetails, 
  rellmHostingPurchaseDetails, 
  notSet
}

class MarketPurchase extends $pb.GeneratedMessage {
  factory MarketPurchase({
    $core.String? id,
    $5.Author? buyer,
    PurchaseType? type,
    MarketProduct? marketProduct,
    MarketSubscription? marketSubscription,
    $core.Iterable<MarketPayment>? marketPayments,
    $core.Iterable<MarketRefund>? marketRefunds,
    MediaStoragePurchaseDetails? mediaStoragePurchaseDetails,
    AIGrantPurchaseDetails? aiGrantPurchaseDetails,
    RellmHostingPurchaseDetails? rellmHostingPurchaseDetails,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (buyer != null) {
      $result.buyer = buyer;
    }
    if (type != null) {
      $result.type = type;
    }
    if (marketProduct != null) {
      $result.marketProduct = marketProduct;
    }
    if (marketSubscription != null) {
      $result.marketSubscription = marketSubscription;
    }
    if (marketPayments != null) {
      $result.marketPayments.addAll(marketPayments);
    }
    if (marketRefunds != null) {
      $result.marketRefunds.addAll(marketRefunds);
    }
    if (mediaStoragePurchaseDetails != null) {
      $result.mediaStoragePurchaseDetails = mediaStoragePurchaseDetails;
    }
    if (aiGrantPurchaseDetails != null) {
      $result.aiGrantPurchaseDetails = aiGrantPurchaseDetails;
    }
    if (rellmHostingPurchaseDetails != null) {
      $result.rellmHostingPurchaseDetails = rellmHostingPurchaseDetails;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  MarketPurchase._() : super();
  factory MarketPurchase.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketPurchase.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, MarketPurchase_Details> _MarketPurchase_DetailsByTag = {
    10 : MarketPurchase_Details.mediaStoragePurchaseDetails,
    11 : MarketPurchase_Details.aiGrantPurchaseDetails,
    12 : MarketPurchase_Details.rellmHostingPurchaseDetails,
    0 : MarketPurchase_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketPurchase', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'buyer', subBuilder: $5.Author.create)
    ..e<PurchaseType>(3, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: PurchaseType.PURCHASE_TYPE_MEDIA_STORAGE, valueOf: PurchaseType.valueOf, enumValues: PurchaseType.values)
    ..aOM<MarketProduct>(4, _omitFieldNames ? '' : 'marketProduct', subBuilder: MarketProduct.create)
    ..aOM<MarketSubscription>(5, _omitFieldNames ? '' : 'marketSubscription', subBuilder: MarketSubscription.create)
    ..pc<MarketPayment>(6, _omitFieldNames ? '' : 'marketPayments', $pb.PbFieldType.PM, subBuilder: MarketPayment.create)
    ..pc<MarketRefund>(7, _omitFieldNames ? '' : 'marketRefunds', $pb.PbFieldType.PM, subBuilder: MarketRefund.create)
    ..aOM<MediaStoragePurchaseDetails>(10, _omitFieldNames ? '' : 'mediaStoragePurchaseDetails', subBuilder: MediaStoragePurchaseDetails.create)
    ..aOM<AIGrantPurchaseDetails>(11, _omitFieldNames ? '' : 'aiGrantPurchaseDetails', subBuilder: AIGrantPurchaseDetails.create)
    ..aOM<RellmHostingPurchaseDetails>(12, _omitFieldNames ? '' : 'rellmHostingPurchaseDetails', subBuilder: RellmHostingPurchaseDetails.create)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketPurchase clone() => MarketPurchase()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketPurchase copyWith(void Function(MarketPurchase) updates) => super.copyWith((message) => updates(message as MarketPurchase)) as MarketPurchase;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketPurchase create() => MarketPurchase._();
  MarketPurchase createEmptyInstance() => create();
  static $pb.PbList<MarketPurchase> createRepeated() => $pb.PbList<MarketPurchase>();
  @$core.pragma('dart2js:noInline')
  static MarketPurchase getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketPurchase>(create);
  static MarketPurchase? _defaultInstance;

  MarketPurchase_Details whichDetails() => _MarketPurchase_DetailsByTag[$_whichOneof(0)]!;
  void clearDetails() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $5.Author get buyer => $_getN(1);
  @$pb.TagNumber(2)
  set buyer($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasBuyer() => $_has(1);
  @$pb.TagNumber(2)
  void clearBuyer() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureBuyer() => $_ensure(1);

  @$pb.TagNumber(3)
  PurchaseType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(PurchaseType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => clearField(3);

  @$pb.TagNumber(4)
  MarketProduct get marketProduct => $_getN(3);
  @$pb.TagNumber(4)
  set marketProduct(MarketProduct v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasMarketProduct() => $_has(3);
  @$pb.TagNumber(4)
  void clearMarketProduct() => clearField(4);
  @$pb.TagNumber(4)
  MarketProduct ensureMarketProduct() => $_ensure(3);

  /// Note: this circular relationship should be handled by the Rust marshaling side.
  @$pb.TagNumber(5)
  MarketSubscription get marketSubscription => $_getN(4);
  @$pb.TagNumber(5)
  set marketSubscription(MarketSubscription v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasMarketSubscription() => $_has(4);
  @$pb.TagNumber(5)
  void clearMarketSubscription() => clearField(5);
  @$pb.TagNumber(5)
  MarketSubscription ensureMarketSubscription() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.List<MarketPayment> get marketPayments => $_getList(5);

  @$pb.TagNumber(7)
  $core.List<MarketRefund> get marketRefunds => $_getList(6);

  @$pb.TagNumber(10)
  MediaStoragePurchaseDetails get mediaStoragePurchaseDetails => $_getN(7);
  @$pb.TagNumber(10)
  set mediaStoragePurchaseDetails(MediaStoragePurchaseDetails v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasMediaStoragePurchaseDetails() => $_has(7);
  @$pb.TagNumber(10)
  void clearMediaStoragePurchaseDetails() => clearField(10);
  @$pb.TagNumber(10)
  MediaStoragePurchaseDetails ensureMediaStoragePurchaseDetails() => $_ensure(7);

  @$pb.TagNumber(11)
  AIGrantPurchaseDetails get aiGrantPurchaseDetails => $_getN(8);
  @$pb.TagNumber(11)
  set aiGrantPurchaseDetails(AIGrantPurchaseDetails v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAiGrantPurchaseDetails() => $_has(8);
  @$pb.TagNumber(11)
  void clearAiGrantPurchaseDetails() => clearField(11);
  @$pb.TagNumber(11)
  AIGrantPurchaseDetails ensureAiGrantPurchaseDetails() => $_ensure(8);

  @$pb.TagNumber(12)
  RellmHostingPurchaseDetails get rellmHostingPurchaseDetails => $_getN(9);
  @$pb.TagNumber(12)
  set rellmHostingPurchaseDetails(RellmHostingPurchaseDetails v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasRellmHostingPurchaseDetails() => $_has(9);
  @$pb.TagNumber(12)
  void clearRellmHostingPurchaseDetails() => clearField(12);
  @$pb.TagNumber(12)
  RellmHostingPurchaseDetails ensureRellmHostingPurchaseDetails() => $_ensure(9);

  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(10);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(10);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(10);
}

class MarketPayment extends $pb.GeneratedMessage {
  factory MarketPayment({
    $core.int? amount,
    $core.int? currency,
    $core.String? marketPurchaseId,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (amount != null) {
      $result.amount = amount;
    }
    if (currency != null) {
      $result.currency = currency;
    }
    if (marketPurchaseId != null) {
      $result.marketPurchaseId = marketPurchaseId;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  MarketPayment._() : super();
  factory MarketPayment.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketPayment.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketPayment', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'amount', $pb.PbFieldType.OU3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'currency', $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'marketPurchaseId')
    ..aOM<$13.Timestamp>(10, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketPayment clone() => MarketPayment()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketPayment copyWith(void Function(MarketPayment) updates) => super.copyWith((message) => updates(message as MarketPayment)) as MarketPayment;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketPayment create() => MarketPayment._();
  MarketPayment createEmptyInstance() => create();
  static $pb.PbList<MarketPayment> createRepeated() => $pb.PbList<MarketPayment>();
  @$core.pragma('dart2js:noInline')
  static MarketPayment getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketPayment>(create);
  static MarketPayment? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get amount => $_getIZ(0);
  @$pb.TagNumber(1)
  set amount($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAmount() => $_has(0);
  @$pb.TagNumber(1)
  void clearAmount() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get currency => $_getIZ(1);
  @$pb.TagNumber(2)
  set currency($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get marketPurchaseId => $_getSZ(2);
  @$pb.TagNumber(3)
  set marketPurchaseId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMarketPurchaseId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMarketPurchaseId() => clearField(3);

  @$pb.TagNumber(10)
  $13.Timestamp get createdAt => $_getN(3);
  @$pb.TagNumber(10)
  set createdAt($13.Timestamp v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
  @$pb.TagNumber(10)
  $13.Timestamp ensureCreatedAt() => $_ensure(3);
}

class MarketPaymentMethod extends $pb.GeneratedMessage {
  factory MarketPaymentMethod() => create();
  MarketPaymentMethod._() : super();
  factory MarketPaymentMethod.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketPaymentMethod.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketPaymentMethod', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketPaymentMethod clone() => MarketPaymentMethod()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketPaymentMethod copyWith(void Function(MarketPaymentMethod) updates) => super.copyWith((message) => updates(message as MarketPaymentMethod)) as MarketPaymentMethod;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketPaymentMethod create() => MarketPaymentMethod._();
  MarketPaymentMethod createEmptyInstance() => create();
  static $pb.PbList<MarketPaymentMethod> createRepeated() => $pb.PbList<MarketPaymentMethod>();
  @$core.pragma('dart2js:noInline')
  static MarketPaymentMethod getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketPaymentMethod>(create);
  static MarketPaymentMethod? _defaultInstance;
}

class MarketRefund extends $pb.GeneratedMessage {
  factory MarketRefund({
    $core.int? amount,
    $core.int? currency,
    $core.String? marketPurchaseId,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (amount != null) {
      $result.amount = amount;
    }
    if (currency != null) {
      $result.currency = currency;
    }
    if (marketPurchaseId != null) {
      $result.marketPurchaseId = marketPurchaseId;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  MarketRefund._() : super();
  factory MarketRefund.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketRefund.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketRefund', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'amount', $pb.PbFieldType.OU3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'currency', $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'marketPurchaseId')
    ..aOM<$13.Timestamp>(10, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketRefund clone() => MarketRefund()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketRefund copyWith(void Function(MarketRefund) updates) => super.copyWith((message) => updates(message as MarketRefund)) as MarketRefund;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketRefund create() => MarketRefund._();
  MarketRefund createEmptyInstance() => create();
  static $pb.PbList<MarketRefund> createRepeated() => $pb.PbList<MarketRefund>();
  @$core.pragma('dart2js:noInline')
  static MarketRefund getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketRefund>(create);
  static MarketRefund? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get amount => $_getIZ(0);
  @$pb.TagNumber(1)
  set amount($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAmount() => $_has(0);
  @$pb.TagNumber(1)
  void clearAmount() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get currency => $_getIZ(1);
  @$pb.TagNumber(2)
  set currency($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get marketPurchaseId => $_getSZ(2);
  @$pb.TagNumber(3)
  set marketPurchaseId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMarketPurchaseId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMarketPurchaseId() => clearField(3);

  @$pb.TagNumber(10)
  $13.Timestamp get createdAt => $_getN(3);
  @$pb.TagNumber(10)
  set createdAt($13.Timestamp v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
  @$pb.TagNumber(10)
  $13.Timestamp ensureCreatedAt() => $_ensure(3);
}

class MarketRefundMethod extends $pb.GeneratedMessage {
  factory MarketRefundMethod() => create();
  MarketRefundMethod._() : super();
  factory MarketRefundMethod.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketRefundMethod.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketRefundMethod', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketRefundMethod clone() => MarketRefundMethod()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketRefundMethod copyWith(void Function(MarketRefundMethod) updates) => super.copyWith((message) => updates(message as MarketRefundMethod)) as MarketRefundMethod;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketRefundMethod create() => MarketRefundMethod._();
  MarketRefundMethod createEmptyInstance() => create();
  static $pb.PbList<MarketRefundMethod> createRepeated() => $pb.PbList<MarketRefundMethod>();
  @$core.pragma('dart2js:noInline')
  static MarketRefundMethod getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketRefundMethod>(create);
  static MarketRefundMethod? _defaultInstance;
}

class MediaStoragePurchaseDetails extends $pb.GeneratedMessage {
  factory MediaStoragePurchaseDetails({
    $fixnum.Int64? allocationBytes,
  }) {
    final $result = create();
    if (allocationBytes != null) {
      $result.allocationBytes = allocationBytes;
    }
    return $result;
  }
  MediaStoragePurchaseDetails._() : super();
  factory MediaStoragePurchaseDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaStoragePurchaseDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaStoragePurchaseDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'allocationBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaStoragePurchaseDetails clone() => MediaStoragePurchaseDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaStoragePurchaseDetails copyWith(void Function(MediaStoragePurchaseDetails) updates) => super.copyWith((message) => updates(message as MediaStoragePurchaseDetails)) as MediaStoragePurchaseDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaStoragePurchaseDetails create() => MediaStoragePurchaseDetails._();
  MediaStoragePurchaseDetails createEmptyInstance() => create();
  static $pb.PbList<MediaStoragePurchaseDetails> createRepeated() => $pb.PbList<MediaStoragePurchaseDetails>();
  @$core.pragma('dart2js:noInline')
  static MediaStoragePurchaseDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaStoragePurchaseDetails>(create);
  static MediaStoragePurchaseDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get allocationBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set allocationBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllocationBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllocationBytes() => clearField(1);
}

class AIGrantPurchaseDetails extends $pb.GeneratedMessage {
  factory AIGrantPurchaseDetails({
    $core.String? aiProviderId,
    $core.Iterable<$core.String>? modelNames,
    $fixnum.Int64? tokens,
  }) {
    final $result = create();
    if (aiProviderId != null) {
      $result.aiProviderId = aiProviderId;
    }
    if (modelNames != null) {
      $result.modelNames.addAll(modelNames);
    }
    if (tokens != null) {
      $result.tokens = tokens;
    }
    return $result;
  }
  AIGrantPurchaseDetails._() : super();
  factory AIGrantPurchaseDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIGrantPurchaseDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIGrantPurchaseDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'aiProviderId')
    ..pPS(2, _omitFieldNames ? '' : 'modelNames')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'tokens', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIGrantPurchaseDetails clone() => AIGrantPurchaseDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIGrantPurchaseDetails copyWith(void Function(AIGrantPurchaseDetails) updates) => super.copyWith((message) => updates(message as AIGrantPurchaseDetails)) as AIGrantPurchaseDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIGrantPurchaseDetails create() => AIGrantPurchaseDetails._();
  AIGrantPurchaseDetails createEmptyInstance() => create();
  static $pb.PbList<AIGrantPurchaseDetails> createRepeated() => $pb.PbList<AIGrantPurchaseDetails>();
  @$core.pragma('dart2js:noInline')
  static AIGrantPurchaseDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIGrantPurchaseDetails>(create);
  static AIGrantPurchaseDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get aiProviderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set aiProviderId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAiProviderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAiProviderId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get modelNames => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get tokens => $_getI64(2);
  @$pb.TagNumber(3)
  set tokens($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTokens() => clearField(3);
}

class RellmHostingPurchaseDetails extends $pb.GeneratedMessage {
  factory RellmHostingPurchaseDetails({
    $fixnum.Int64? dbSizeBytes,
    $fixnum.Int64? minioSizeBytes,
    $core.String? domain,
    $core.String? contactEmail,
    $core.String? additionalInformation,
  }) {
    final $result = create();
    if (dbSizeBytes != null) {
      $result.dbSizeBytes = dbSizeBytes;
    }
    if (minioSizeBytes != null) {
      $result.minioSizeBytes = minioSizeBytes;
    }
    if (domain != null) {
      $result.domain = domain;
    }
    if (contactEmail != null) {
      $result.contactEmail = contactEmail;
    }
    if (additionalInformation != null) {
      $result.additionalInformation = additionalInformation;
    }
    return $result;
  }
  RellmHostingPurchaseDetails._() : super();
  factory RellmHostingPurchaseDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RellmHostingPurchaseDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RellmHostingPurchaseDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'dbSizeBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'minioSizeBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'domain')
    ..aOS(4, _omitFieldNames ? '' : 'contactEmail')
    ..aOS(5, _omitFieldNames ? '' : 'additionalInformation')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RellmHostingPurchaseDetails clone() => RellmHostingPurchaseDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RellmHostingPurchaseDetails copyWith(void Function(RellmHostingPurchaseDetails) updates) => super.copyWith((message) => updates(message as RellmHostingPurchaseDetails)) as RellmHostingPurchaseDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RellmHostingPurchaseDetails create() => RellmHostingPurchaseDetails._();
  RellmHostingPurchaseDetails createEmptyInstance() => create();
  static $pb.PbList<RellmHostingPurchaseDetails> createRepeated() => $pb.PbList<RellmHostingPurchaseDetails>();
  @$core.pragma('dart2js:noInline')
  static RellmHostingPurchaseDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RellmHostingPurchaseDetails>(create);
  static RellmHostingPurchaseDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get dbSizeBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set dbSizeBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDbSizeBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDbSizeBytes() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get minioSizeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set minioSizeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinioSizeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinioSizeBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get domain => $_getSZ(2);
  @$pb.TagNumber(3)
  set domain($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDomain() => $_has(2);
  @$pb.TagNumber(3)
  void clearDomain() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get contactEmail => $_getSZ(3);
  @$pb.TagNumber(4)
  set contactEmail($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContactEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearContactEmail() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get additionalInformation => $_getSZ(4);
  @$pb.TagNumber(5)
  set additionalInformation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalInformation() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalInformation() => clearField(5);
}

enum MarketSubscription_Details {
  mediaStorageSubscriptionDetails, 
  aiGrantSubscriptionDetails, 
  rellmHostingSubscriptionDetails, 
  notSet
}

class MarketSubscription extends $pb.GeneratedMessage {
  factory MarketSubscription({
    $core.String? id,
    $5.Author? buyer,
    PurchaseType? type,
    PurchasePeriod? period,
    $core.int? amount,
    $core.int? currency,
    MarketProduct? marketProduct,
    $core.Iterable<MarketPurchase>? billingHistory,
    MediaStorageSubscriptionDetails? mediaStorageSubscriptionDetails,
    AIGrantSubscriptionDetails? aiGrantSubscriptionDetails,
    RellmHostingSubscriptionDetails? rellmHostingSubscriptionDetails,
    $13.Timestamp? createdAt,
    $13.Timestamp? renewsAt,
    $13.Timestamp? endedAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (buyer != null) {
      $result.buyer = buyer;
    }
    if (type != null) {
      $result.type = type;
    }
    if (period != null) {
      $result.period = period;
    }
    if (amount != null) {
      $result.amount = amount;
    }
    if (currency != null) {
      $result.currency = currency;
    }
    if (marketProduct != null) {
      $result.marketProduct = marketProduct;
    }
    if (billingHistory != null) {
      $result.billingHistory.addAll(billingHistory);
    }
    if (mediaStorageSubscriptionDetails != null) {
      $result.mediaStorageSubscriptionDetails = mediaStorageSubscriptionDetails;
    }
    if (aiGrantSubscriptionDetails != null) {
      $result.aiGrantSubscriptionDetails = aiGrantSubscriptionDetails;
    }
    if (rellmHostingSubscriptionDetails != null) {
      $result.rellmHostingSubscriptionDetails = rellmHostingSubscriptionDetails;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (renewsAt != null) {
      $result.renewsAt = renewsAt;
    }
    if (endedAt != null) {
      $result.endedAt = endedAt;
    }
    return $result;
  }
  MarketSubscription._() : super();
  factory MarketSubscription.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketSubscription.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, MarketSubscription_Details> _MarketSubscription_DetailsByTag = {
    10 : MarketSubscription_Details.mediaStorageSubscriptionDetails,
    11 : MarketSubscription_Details.aiGrantSubscriptionDetails,
    12 : MarketSubscription_Details.rellmHostingSubscriptionDetails,
    0 : MarketSubscription_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketSubscription', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'buyer', subBuilder: $5.Author.create)
    ..e<PurchaseType>(3, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: PurchaseType.PURCHASE_TYPE_MEDIA_STORAGE, valueOf: PurchaseType.valueOf, enumValues: PurchaseType.values)
    ..e<PurchasePeriod>(4, _omitFieldNames ? '' : 'period', $pb.PbFieldType.OE, defaultOrMaker: PurchasePeriod.PURCHASE_PERIOD_INDEFINITE, valueOf: PurchasePeriod.valueOf, enumValues: PurchasePeriod.values)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'amount', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'currency', $pb.PbFieldType.OU3)
    ..aOM<MarketProduct>(7, _omitFieldNames ? '' : 'marketProduct', subBuilder: MarketProduct.create)
    ..pc<MarketPurchase>(8, _omitFieldNames ? '' : 'billingHistory', $pb.PbFieldType.PM, subBuilder: MarketPurchase.create)
    ..aOM<MediaStorageSubscriptionDetails>(10, _omitFieldNames ? '' : 'mediaStorageSubscriptionDetails', subBuilder: MediaStorageSubscriptionDetails.create)
    ..aOM<AIGrantSubscriptionDetails>(11, _omitFieldNames ? '' : 'aiGrantSubscriptionDetails', subBuilder: AIGrantSubscriptionDetails.create)
    ..aOM<RellmHostingSubscriptionDetails>(12, _omitFieldNames ? '' : 'rellmHostingSubscriptionDetails', subBuilder: RellmHostingSubscriptionDetails.create)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(21, _omitFieldNames ? '' : 'renewsAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(22, _omitFieldNames ? '' : 'endedAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarketSubscription clone() => MarketSubscription()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarketSubscription copyWith(void Function(MarketSubscription) updates) => super.copyWith((message) => updates(message as MarketSubscription)) as MarketSubscription;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarketSubscription create() => MarketSubscription._();
  MarketSubscription createEmptyInstance() => create();
  static $pb.PbList<MarketSubscription> createRepeated() => $pb.PbList<MarketSubscription>();
  @$core.pragma('dart2js:noInline')
  static MarketSubscription getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarketSubscription>(create);
  static MarketSubscription? _defaultInstance;

  MarketSubscription_Details whichDetails() => _MarketSubscription_DetailsByTag[$_whichOneof(0)]!;
  void clearDetails() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $5.Author get buyer => $_getN(1);
  @$pb.TagNumber(2)
  set buyer($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasBuyer() => $_has(1);
  @$pb.TagNumber(2)
  void clearBuyer() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureBuyer() => $_ensure(1);

  @$pb.TagNumber(3)
  PurchaseType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(PurchaseType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => clearField(3);

  @$pb.TagNumber(4)
  PurchasePeriod get period => $_getN(3);
  @$pb.TagNumber(4)
  set period(PurchasePeriod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPeriod() => $_has(3);
  @$pb.TagNumber(4)
  void clearPeriod() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get amount => $_getIZ(4);
  @$pb.TagNumber(5)
  set amount($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAmount() => $_has(4);
  @$pb.TagNumber(5)
  void clearAmount() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get currency => $_getIZ(5);
  @$pb.TagNumber(6)
  set currency($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCurrency() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrency() => clearField(6);

  /// Note: marshaling should handle the circular relationship here gracefully.
  @$pb.TagNumber(7)
  MarketProduct get marketProduct => $_getN(6);
  @$pb.TagNumber(7)
  set marketProduct(MarketProduct v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasMarketProduct() => $_has(6);
  @$pb.TagNumber(7)
  void clearMarketProduct() => clearField(7);
  @$pb.TagNumber(7)
  MarketProduct ensureMarketProduct() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.List<MarketPurchase> get billingHistory => $_getList(7);

  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails get mediaStorageSubscriptionDetails => $_getN(8);
  @$pb.TagNumber(10)
  set mediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasMediaStorageSubscriptionDetails() => $_has(8);
  @$pb.TagNumber(10)
  void clearMediaStorageSubscriptionDetails() => clearField(10);
  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails ensureMediaStorageSubscriptionDetails() => $_ensure(8);

  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails get aiGrantSubscriptionDetails => $_getN(9);
  @$pb.TagNumber(11)
  set aiGrantSubscriptionDetails(AIGrantSubscriptionDetails v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAiGrantSubscriptionDetails() => $_has(9);
  @$pb.TagNumber(11)
  void clearAiGrantSubscriptionDetails() => clearField(11);
  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails ensureAiGrantSubscriptionDetails() => $_ensure(9);

  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails get rellmHostingSubscriptionDetails => $_getN(10);
  @$pb.TagNumber(12)
  set rellmHostingSubscriptionDetails(RellmHostingSubscriptionDetails v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasRellmHostingSubscriptionDetails() => $_has(10);
  @$pb.TagNumber(12)
  void clearRellmHostingSubscriptionDetails() => clearField(12);
  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails ensureRellmHostingSubscriptionDetails() => $_ensure(10);

  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(11);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(11);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(11);

  @$pb.TagNumber(21)
  $13.Timestamp get renewsAt => $_getN(12);
  @$pb.TagNumber(21)
  set renewsAt($13.Timestamp v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasRenewsAt() => $_has(12);
  @$pb.TagNumber(21)
  void clearRenewsAt() => clearField(21);
  @$pb.TagNumber(21)
  $13.Timestamp ensureRenewsAt() => $_ensure(12);

  /// If set, the MarketSubscription is unavailable
  @$pb.TagNumber(22)
  $13.Timestamp get endedAt => $_getN(13);
  @$pb.TagNumber(22)
  set endedAt($13.Timestamp v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasEndedAt() => $_has(13);
  @$pb.TagNumber(22)
  void clearEndedAt() => clearField(22);
  @$pb.TagNumber(22)
  $13.Timestamp ensureEndedAt() => $_ensure(13);
}

class MediaStorageSubscriptionDetails extends $pb.GeneratedMessage {
  factory MediaStorageSubscriptionDetails({
    $fixnum.Int64? allocationBytes,
  }) {
    final $result = create();
    if (allocationBytes != null) {
      $result.allocationBytes = allocationBytes;
    }
    return $result;
  }
  MediaStorageSubscriptionDetails._() : super();
  factory MediaStorageSubscriptionDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaStorageSubscriptionDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaStorageSubscriptionDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'allocationBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaStorageSubscriptionDetails clone() => MediaStorageSubscriptionDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaStorageSubscriptionDetails copyWith(void Function(MediaStorageSubscriptionDetails) updates) => super.copyWith((message) => updates(message as MediaStorageSubscriptionDetails)) as MediaStorageSubscriptionDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaStorageSubscriptionDetails create() => MediaStorageSubscriptionDetails._();
  MediaStorageSubscriptionDetails createEmptyInstance() => create();
  static $pb.PbList<MediaStorageSubscriptionDetails> createRepeated() => $pb.PbList<MediaStorageSubscriptionDetails>();
  @$core.pragma('dart2js:noInline')
  static MediaStorageSubscriptionDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaStorageSubscriptionDetails>(create);
  static MediaStorageSubscriptionDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get allocationBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set allocationBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllocationBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllocationBytes() => clearField(1);
}

class AIGrantSubscriptionDetails extends $pb.GeneratedMessage {
  factory AIGrantSubscriptionDetails({
    $core.String? aiProviderId,
    $core.Iterable<$core.String>? modelNames,
    $fixnum.Int64? tokens,
  }) {
    final $result = create();
    if (aiProviderId != null) {
      $result.aiProviderId = aiProviderId;
    }
    if (modelNames != null) {
      $result.modelNames.addAll(modelNames);
    }
    if (tokens != null) {
      $result.tokens = tokens;
    }
    return $result;
  }
  AIGrantSubscriptionDetails._() : super();
  factory AIGrantSubscriptionDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIGrantSubscriptionDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIGrantSubscriptionDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'aiProviderId')
    ..pPS(2, _omitFieldNames ? '' : 'modelNames')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'tokens', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIGrantSubscriptionDetails clone() => AIGrantSubscriptionDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIGrantSubscriptionDetails copyWith(void Function(AIGrantSubscriptionDetails) updates) => super.copyWith((message) => updates(message as AIGrantSubscriptionDetails)) as AIGrantSubscriptionDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIGrantSubscriptionDetails create() => AIGrantSubscriptionDetails._();
  AIGrantSubscriptionDetails createEmptyInstance() => create();
  static $pb.PbList<AIGrantSubscriptionDetails> createRepeated() => $pb.PbList<AIGrantSubscriptionDetails>();
  @$core.pragma('dart2js:noInline')
  static AIGrantSubscriptionDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIGrantSubscriptionDetails>(create);
  static AIGrantSubscriptionDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get aiProviderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set aiProviderId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAiProviderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAiProviderId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get modelNames => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get tokens => $_getI64(2);
  @$pb.TagNumber(3)
  set tokens($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTokens() => clearField(3);
}

class RellmHostingSubscriptionDetails extends $pb.GeneratedMessage {
  factory RellmHostingSubscriptionDetails({
    $fixnum.Int64? dbSizeBytes,
    $fixnum.Int64? minioSizeBytes,
    $core.String? domain,
    $core.String? contactEmail,
    $core.String? additionalInformation,
  }) {
    final $result = create();
    if (dbSizeBytes != null) {
      $result.dbSizeBytes = dbSizeBytes;
    }
    if (minioSizeBytes != null) {
      $result.minioSizeBytes = minioSizeBytes;
    }
    if (domain != null) {
      $result.domain = domain;
    }
    if (contactEmail != null) {
      $result.contactEmail = contactEmail;
    }
    if (additionalInformation != null) {
      $result.additionalInformation = additionalInformation;
    }
    return $result;
  }
  RellmHostingSubscriptionDetails._() : super();
  factory RellmHostingSubscriptionDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RellmHostingSubscriptionDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RellmHostingSubscriptionDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'dbSizeBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'minioSizeBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'domain')
    ..aOS(4, _omitFieldNames ? '' : 'contactEmail')
    ..aOS(5, _omitFieldNames ? '' : 'additionalInformation')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RellmHostingSubscriptionDetails clone() => RellmHostingSubscriptionDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RellmHostingSubscriptionDetails copyWith(void Function(RellmHostingSubscriptionDetails) updates) => super.copyWith((message) => updates(message as RellmHostingSubscriptionDetails)) as RellmHostingSubscriptionDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RellmHostingSubscriptionDetails create() => RellmHostingSubscriptionDetails._();
  RellmHostingSubscriptionDetails createEmptyInstance() => create();
  static $pb.PbList<RellmHostingSubscriptionDetails> createRepeated() => $pb.PbList<RellmHostingSubscriptionDetails>();
  @$core.pragma('dart2js:noInline')
  static RellmHostingSubscriptionDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RellmHostingSubscriptionDetails>(create);
  static RellmHostingSubscriptionDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get dbSizeBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set dbSizeBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDbSizeBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDbSizeBytes() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get minioSizeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set minioSizeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinioSizeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinioSizeBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get domain => $_getSZ(2);
  @$pb.TagNumber(3)
  set domain($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDomain() => $_has(2);
  @$pb.TagNumber(3)
  void clearDomain() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get contactEmail => $_getSZ(3);
  @$pb.TagNumber(4)
  set contactEmail($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContactEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearContactEmail() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get additionalInformation => $_getSZ(4);
  @$pb.TagNumber(5)
  set additionalInformation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalInformation() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalInformation() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
