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
import 'permissions.pbenum.dart' as $15;

export 'market.pbenum.dart';

enum MarketProduct_Details {
  mediaStorageSubscriptionDetails, 
  aiGrantSubscriptionDetails, 
  rellmHostingSubscriptionDetails, 
  permissionsAccessSubscriptionDetails, 
  notSet
}

/// An actual subscribable product listed on, say, https://rellm.org/market -- what an admin creates
/// via `CreateMarketProduct`/edits via `UpdateMarketProduct`, and what a buyer actually purchases via
/// `MakeMarketPurchase`. `market_settings.enabled` (see `server_configuration.proto`) gates whether a
/// server's Market is browsable/purchasable at all, independent of any individual product's own
/// `delisted_at`. Listed/delisted by clients by setting `delisted_at` (though the actual date
/// supplied by the client is ignored -- see that field's own doc).
class MarketProduct extends $pb.GeneratedMessage {
  factory MarketProduct({
    $core.String? id,
    PurchaseType? type,
    PurchasePeriod? period,
    $core.int? amount,
    $core.int? currency,
    $core.int? availableCount,
    $core.int? soldCount,
    MediaStorageSubscriptionDetails? mediaStorageSubscriptionDetails,
    AIGrantSubscriptionDetails? aiGrantSubscriptionDetails,
    RellmHostingSubscriptionDetails? rellmHostingSubscriptionDetails,
    PermissionsAccessSubscriptionDetails? permissionsAccessSubscriptionDetails,
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
    if (availableCount != null) {
      $result.availableCount = availableCount;
    }
    if (soldCount != null) {
      $result.soldCount = soldCount;
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
    if (permissionsAccessSubscriptionDetails != null) {
      $result.permissionsAccessSubscriptionDetails = permissionsAccessSubscriptionDetails;
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
    13 : MarketProduct_Details.permissionsAccessSubscriptionDetails,
    0 : MarketProduct_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketProduct', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..e<PurchaseType>(2, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: PurchaseType.PURCHASE_TYPE_MEDIA_STORAGE, valueOf: PurchaseType.valueOf, enumValues: PurchaseType.values)
    ..e<PurchasePeriod>(3, _omitFieldNames ? '' : 'period', $pb.PbFieldType.OE, defaultOrMaker: PurchasePeriod.PURCHASE_PERIOD_INDEFINITE, valueOf: PurchasePeriod.valueOf, enumValues: PurchasePeriod.values)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'amount', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'currency', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'availableCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'soldCount', $pb.PbFieldType.OU3)
    ..aOM<MediaStorageSubscriptionDetails>(10, _omitFieldNames ? '' : 'mediaStorageSubscriptionDetails', subBuilder: MediaStorageSubscriptionDetails.create)
    ..aOM<AIGrantSubscriptionDetails>(11, _omitFieldNames ? '' : 'aiGrantSubscriptionDetails', subBuilder: AIGrantSubscriptionDetails.create)
    ..aOM<RellmHostingSubscriptionDetails>(12, _omitFieldNames ? '' : 'rellmHostingSubscriptionDetails', subBuilder: RellmHostingSubscriptionDetails.create)
    ..aOM<PermissionsAccessSubscriptionDetails>(13, _omitFieldNames ? '' : 'permissionsAccessSubscriptionDetails', subBuilder: PermissionsAccessSubscriptionDetails.create)
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

  /// What this product grants once purchased -- see `PurchaseType`'s own doc for what each value
  /// does. Never changeable after product creation (`UpdateMarketProduct` silently ignores any
  /// change to this field) -- changing what a product *is* after people have already bought it would
  /// silently change existing buyers' entitlements out from under them; a product whose type needs
  /// to change is delisted and replaced with a new one instead.
  @$pb.TagNumber(2)
  PurchaseType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(PurchaseType v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  /// How often this product bills, if at all -- see `PurchasePeriod`'s own doc. Never changeable
  /// after product creation, same reasoning as `type` above.
  @$pb.TagNumber(3)
  PurchasePeriod get period => $_getN(2);
  @$pb.TagNumber(3)
  set period(PurchasePeriod v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPeriod() => $_has(2);
  @$pb.TagNumber(3)
  void clearPeriod() => clearField(3);

  /// The price, in the smallest unit of `currency` (e.g. cents for USD) -- except for a
  /// zero-decimal currency like JPY, where this is already the whole unit (see
  /// `logic::stripe_sync::is_zero_decimal_currency`).
  @$pb.TagNumber(4)
  $core.int get amount => $_getIZ(3);
  @$pb.TagNumber(4)
  set amount($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAmount() => $_has(3);
  @$pb.TagNumber(4)
  void clearAmount() => clearField(4);

  /// The ISO 4217 numeric currency code this product is priced in (e.g. `840` for USD, `392` for
  /// JPY) -- see `logic::market_summary`'s currency table for the full set of currencies a server
  /// actually supports pricing in today.
  @$pb.TagNumber(5)
  $core.int get currency => $_getIZ(4);
  @$pb.TagNumber(5)
  set currency($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => clearField(5);

  /// Number of subscription "slots" available for this product (admin-set) -- `0` means unlimited.
  /// Once `sold_count >= available_count` (and `available_count > 0`), `MakeMarketPurchase` rejects
  /// further purchases with `product_sold_out`.
  @$pb.TagNumber(6)
  $core.int get availableCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set availableCount($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAvailableCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearAvailableCount() => clearField(6);

  /// Number of subscriptions actually sold, maintained server-side (never client-settable --
  /// `UpdateMarketProduct` silently ignores any client-sent value for this field). Incremented when
  /// a purchase's Stripe Checkout Session completes; decremented when the resulting
  /// `MarketSubscription` is actually canceled (`CancelMarketSubscription`), freeing the slot for a
  /// new buyer.
  @$pb.TagNumber(7)
  $core.int get soldCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set soldCount($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSoldCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearSoldCount() => clearField(7);

  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails get mediaStorageSubscriptionDetails => $_getN(7);
  @$pb.TagNumber(10)
  set mediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasMediaStorageSubscriptionDetails() => $_has(7);
  @$pb.TagNumber(10)
  void clearMediaStorageSubscriptionDetails() => clearField(10);
  @$pb.TagNumber(10)
  MediaStorageSubscriptionDetails ensureMediaStorageSubscriptionDetails() => $_ensure(7);

  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails get aiGrantSubscriptionDetails => $_getN(8);
  @$pb.TagNumber(11)
  set aiGrantSubscriptionDetails(AIGrantSubscriptionDetails v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAiGrantSubscriptionDetails() => $_has(8);
  @$pb.TagNumber(11)
  void clearAiGrantSubscriptionDetails() => clearField(11);
  @$pb.TagNumber(11)
  AIGrantSubscriptionDetails ensureAiGrantSubscriptionDetails() => $_ensure(8);

  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails get rellmHostingSubscriptionDetails => $_getN(9);
  @$pb.TagNumber(12)
  set rellmHostingSubscriptionDetails(RellmHostingSubscriptionDetails v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasRellmHostingSubscriptionDetails() => $_has(9);
  @$pb.TagNumber(12)
  void clearRellmHostingSubscriptionDetails() => clearField(12);
  @$pb.TagNumber(12)
  RellmHostingSubscriptionDetails ensureRellmHostingSubscriptionDetails() => $_ensure(9);

  @$pb.TagNumber(13)
  PermissionsAccessSubscriptionDetails get permissionsAccessSubscriptionDetails => $_getN(10);
  @$pb.TagNumber(13)
  set permissionsAccessSubscriptionDetails(PermissionsAccessSubscriptionDetails v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasPermissionsAccessSubscriptionDetails() => $_has(10);
  @$pb.TagNumber(13)
  void clearPermissionsAccessSubscriptionDetails() => clearField(13);
  @$pb.TagNumber(13)
  PermissionsAccessSubscriptionDetails ensurePermissionsAccessSubscriptionDetails() => $_ensure(10);

  /// When this product was created. Server-stamped -- `CreateMarketProduct` ignores any client-sent
  /// value.
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

  /// If set, the MarketProduct is not purchasable -- still shown to admins (see
  /// `GetMarketProductsResponse.market_products`' own doc), but hidden from every other caller and
  /// rejected by `MakeMarketPurchase`. Note: clients toggle listings by setting this, but the server
  /// will always set it to the time of the request, not the time sent *by* the request.
  @$pb.TagNumber(21)
  $13.Timestamp get delistedAt => $_getN(12);
  @$pb.TagNumber(21)
  set delistedAt($13.Timestamp v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasDelistedAt() => $_has(12);
  @$pb.TagNumber(21)
  void clearDelistedAt() => clearField(21);
  @$pb.TagNumber(21)
  $13.Timestamp ensureDelistedAt() => $_ensure(12);
}

/// Request to get products available for purchase on a Rellm server. *Unauthenticated* --
/// `GetMarketProducts` never requires a signed-in caller (see that RPC's own doc), so anyone can
/// browse a server's Market without an account, including from another federated server (see
/// `rellm.proto`'s "Federated Markets" doc). For now, there are few enough products per server that
/// this has no filtering/paging parameters.
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

  /// Every non-delisted `MarketProduct`, plus delisted ones too if the caller is a signed-in admin
  /// on this server (so admins can still find/relist/edit a delisted product from the same `/market`
  /// page everyone else sees).
  @$pb.TagNumber(1)
  $core.List<MarketProduct> get marketProducts => $_getList(0);
}

/// Request to get MarketSubscriptions -- self-scoped to the current user's own
/// (`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE`, the default -- there's no way to fetch another
/// user's own subscriptions this way, even as an admin), or -- for an admin only --
/// `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`, every `PURCHASE_TYPE_RELLM_HOSTING`
/// subscription across every buyer, for the `/market/fulfillment` admin page.
class GetMarketSubscriptionsRequest extends $pb.GeneratedMessage {
  factory GetMarketSubscriptionsRequest({
    GetMarketSubscriptionsRequestType? requestType,
  }) {
    final $result = create();
    if (requestType != null) {
      $result.requestType = requestType;
    }
    return $result;
  }
  GetMarketSubscriptionsRequest._() : super();
  factory GetMarketSubscriptionsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMarketSubscriptionsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMarketSubscriptionsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..e<GetMarketSubscriptionsRequestType>(1, _omitFieldNames ? '' : 'requestType', $pb.PbFieldType.OE, defaultOrMaker: GetMarketSubscriptionsRequestType.GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE, valueOf: GetMarketSubscriptionsRequestType.valueOf, enumValues: GetMarketSubscriptionsRequestType.values)
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

  /// Which of the two views below to return. Defaults to
  /// `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE` (proto3's implicit `0` default), so existing
  /// callers that predate this field keep getting their own subscriptions, not the admin view.
  @$pb.TagNumber(1)
  GetMarketSubscriptionsRequestType get requestType => $_getN(0);
  @$pb.TagNumber(1)
  set requestType(GetMarketSubscriptionsRequestType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestType() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestType() => clearField(1);
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

  /// For `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE`: the caller's own subscriptions, newest
  /// first. For `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`: every
  /// `PURCHASE_TYPE_RELLM_HOSTING` subscription across every buyer, oldest first (so the oldest
  /// unfulfilled order surfaces at the top of `/market/fulfillment`).
  @$pb.TagNumber(1)
  $core.List<MarketSubscription> get marketSubscriptions => $_getList(0);
}

/// *Authenticated*. Buys `market_product_id` for the current user, starting (or continuing) a
/// Stripe Checkout flow -- see `MakeMarketPurchaseResponse.checkout_url`. No `MarketPurchase`/
/// `MarketSubscription` is created by this call itself; that only happens once Stripe confirms
/// payment via webhook, so an abandoned checkout never leaves a half-created purchase behind.
/// Rejected outright (`market_disabled`) if `market_settings.enabled` is false -- checked first,
/// ahead of every product-specific precondition (delisted/sold-out/Stripe-not-configured/etc.),
/// since an admin who's closed Market entirely shouldn't have that bypassable by simply knowing a
/// still-valid product id.
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

/// A pending Stripe Checkout Session, ready to redirect the buyer's browser to.
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

  /// Redirect the buyer's browser here (a Stripe-hosted Checkout page) to complete payment. Expires
  /// after Stripe's own Checkout Session timeout if never completed -- since no `MarketPurchase` row
  /// is created until the webhook fires (see this message's own request's doc), an abandoned/expired
  /// checkout leaves no trace at all.
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
  permissionsAccessPurchaseDetails, 
  notSet
}

/// One completed billing event -- the initial purchase or a later recurring renewal charge -- for a
/// single product. Created only from `web::stripe_webhook` (the initial purchase, on
/// `checkout.session.completed`) or `logic::market_renewal` (each subsequent recurring charge),
/// never directly by `MakeMarketPurchase` itself (see that RPC's own doc). MarketPurchases are
/// immutable via the API+CLI once created -- there is no `UpdateMarketPurchase` RPC; the payments,
/// refunds, and (for a subscription) fulfillment information that accumulate against a purchase over
/// time live in their own separate messages/tables instead of ever rewriting this one.
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
    PermissionsAccessPurchaseDetails? permissionsAccessPurchaseDetails,
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
    if (permissionsAccessPurchaseDetails != null) {
      $result.permissionsAccessPurchaseDetails = permissionsAccessPurchaseDetails;
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
    13 : MarketPurchase_Details.permissionsAccessPurchaseDetails,
    0 : MarketPurchase_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketPurchase', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13])
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
    ..aOM<PermissionsAccessPurchaseDetails>(13, _omitFieldNames ? '' : 'permissionsAccessPurchaseDetails', subBuilder: PermissionsAccessPurchaseDetails.create)
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

  /// Who bought this.
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

  /// What this purchase grants -- copied from (and always matching) `market_product.type` at the
  /// time of purchase. Denormalized here (rather than requiring a lookup through `market_product`)
  /// so a client can branch on `details`' oneof case without needing `market_product` populated.
  @$pb.TagNumber(3)
  PurchaseType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(PurchaseType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => clearField(3);

  /// The `MarketProduct` this purchase was made against, as it existed at the time it was fetched --
  /// may since have changed price/details/been delisted; this purchase's own `amount`-equivalent
  /// fields live on whichever `MarketPayment`s are attached, not here.
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

  /// The subscription this purchase belongs to -- every purchase gets one, including a
  /// `PURCHASE_PERIOD_INDEFINITE` one-time purchase (see `MarketSubscription`'s own doc), so
  /// `Optional` here really only means "always unset when this `MarketPurchase` is itself embedded
  /// inside a `MarketSubscription.billing_history`" (there'd be no point recursing into the same
  /// subscription again). Note: this circular relationship should be handled by the Rust marshaling
  /// side.
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

  /// Every payment recorded against this purchase, oldest first -- ordinarily just one, but a failed
  /// charge that's later retried (see `logic::market_renewal`) can leave more than one row.
  @$pb.TagNumber(6)
  $core.List<MarketPayment> get marketPayments => $_getList(5);

  /// Every refund recorded against this purchase, oldest first -- empty for the common case of a
  /// purchase that was never refunded.
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

  @$pb.TagNumber(13)
  PermissionsAccessPurchaseDetails get permissionsAccessPurchaseDetails => $_getN(10);
  @$pb.TagNumber(13)
  set permissionsAccessPurchaseDetails(PermissionsAccessPurchaseDetails v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasPermissionsAccessPurchaseDetails() => $_has(10);
  @$pb.TagNumber(13)
  void clearPermissionsAccessPurchaseDetails() => clearField(13);
  @$pb.TagNumber(13)
  PermissionsAccessPurchaseDetails ensurePermissionsAccessPurchaseDetails() => $_ensure(10);

  /// When this purchase was recorded -- i.e. when the Stripe webhook/renewal job actually processed
  /// it, not when the buyer started checkout.
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
}

/// A single successful charge against a `MarketPurchase` -- one row per completed Stripe
/// `PaymentIntent` (the initial purchase's, or a later renewal's). Backed by the same
/// `market_payments` table as `MarketRefund` (a positive `amount` row marshals to a `MarketPayment`,
/// a negative one to a `MarketRefund` -- see that message's own doc), so a `MarketPayment` is never
/// itself edited or deleted once created; a refund is always its own separate row/message.
class MarketPayment extends $pb.GeneratedMessage {
  factory MarketPayment({
    $core.int? amount,
    $core.int? currency,
    $core.String? marketPurchaseId,
    MarketPaymentMethod? method,
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
    if (method != null) {
      $result.method = method;
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
    ..aOM<MarketPaymentMethod>(4, _omitFieldNames ? '' : 'method', subBuilder: MarketPaymentMethod.create)
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

  /// The amount actually charged, in the same unit `MarketProduct.amount` uses (smallest unit of
  /// `currency`, except for a zero-decimal currency like JPY).
  @$pb.TagNumber(1)
  $core.int get amount => $_getIZ(0);
  @$pb.TagNumber(1)
  set amount($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAmount() => $_has(0);
  @$pb.TagNumber(1)
  void clearAmount() => clearField(1);

  /// The ISO 4217 numeric currency code `amount` is denominated in -- copied from the purchase's own
  /// product at charge time.
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

  /// The card actually charged, if known/resolvable at the time this MarketPayment was recorded.
  @$pb.TagNumber(4)
  MarketPaymentMethod get method => $_getN(3);
  @$pb.TagNumber(4)
  set method(MarketPaymentMethod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasMethod() => $_has(3);
  @$pb.TagNumber(4)
  void clearMethod() => clearField(4);
  @$pb.TagNumber(4)
  MarketPaymentMethod ensureMethod() => $_ensure(3);

  /// When this charge succeeded.
  @$pb.TagNumber(10)
  $13.Timestamp get createdAt => $_getN(4);
  @$pb.TagNumber(10)
  set createdAt($13.Timestamp v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
  @$pb.TagNumber(10)
  $13.Timestamp ensureCreatedAt() => $_ensure(4);
}

/// Card details for a MarketPayment, resolved from Stripe at charge time (Stripe's own
/// `PaymentMethod.card` object). Unset entirely if the payment wasn't card-based or details
/// couldn't be resolved. Never carries anything more sensitive than what Stripe itself considers
/// safe to display (brand/last4/expiry) -- never a full card number.
class MarketPaymentMethod extends $pb.GeneratedMessage {
  factory MarketPaymentMethod({
    $core.String? cardBrand,
    $core.String? cardLast4,
    $core.int? cardExpMonth,
    $core.int? cardExpYear,
  }) {
    final $result = create();
    if (cardBrand != null) {
      $result.cardBrand = cardBrand;
    }
    if (cardLast4 != null) {
      $result.cardLast4 = cardLast4;
    }
    if (cardExpMonth != null) {
      $result.cardExpMonth = cardExpMonth;
    }
    if (cardExpYear != null) {
      $result.cardExpYear = cardExpYear;
    }
    return $result;
  }
  MarketPaymentMethod._() : super();
  factory MarketPaymentMethod.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketPaymentMethod.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketPaymentMethod', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'cardBrand')
    ..aOS(2, _omitFieldNames ? '' : 'cardLast4')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'cardExpMonth', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'cardExpYear', $pb.PbFieldType.OU3)
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

  /// E.g. "visa", "mastercard", "amex".
  @$pb.TagNumber(1)
  $core.String get cardBrand => $_getSZ(0);
  @$pb.TagNumber(1)
  set cardBrand($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCardBrand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCardBrand() => clearField(1);

  /// Last 4 digits of the card number.
  @$pb.TagNumber(2)
  $core.String get cardLast4 => $_getSZ(1);
  @$pb.TagNumber(2)
  set cardLast4($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCardLast4() => $_has(1);
  @$pb.TagNumber(2)
  void clearCardLast4() => clearField(2);

  /// 1-12.
  @$pb.TagNumber(3)
  $core.int get cardExpMonth => $_getIZ(2);
  @$pb.TagNumber(3)
  set cardExpMonth($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCardExpMonth() => $_has(2);
  @$pb.TagNumber(3)
  void clearCardExpMonth() => clearField(3);

  /// 4-digit year.
  @$pb.TagNumber(4)
  $core.int get cardExpYear => $_getIZ(3);
  @$pb.TagNumber(4)
  set cardExpYear($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCardExpYear() => $_has(3);
  @$pb.TagNumber(4)
  void clearCardExpYear() => clearField(4);
}

/// A single refund issued against a `MarketPurchase`'s payment -- see `MarketPayment`'s own doc for
/// how this and `MarketPayment` share the same underlying `market_payments` table.
class MarketRefund extends $pb.GeneratedMessage {
  factory MarketRefund({
    $core.int? amount,
    $core.int? currency,
    $core.String? marketPurchaseId,
    MarketRefundMethod? method,
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
    if (method != null) {
      $result.method = method;
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
    ..aOM<MarketRefundMethod>(4, _omitFieldNames ? '' : 'method', subBuilder: MarketRefundMethod.create)
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

  /// The amount refunded, in the same unit the original `MarketPayment.amount` was charged in --
  /// always positive here (the underlying row's negative `amount` is what distinguishes a refund
  /// from a payment; this message itself never exposes the sign).
  @$pb.TagNumber(1)
  $core.int get amount => $_getIZ(0);
  @$pb.TagNumber(1)
  set amount($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAmount() => $_has(0);
  @$pb.TagNumber(1)
  void clearAmount() => clearField(1);

  /// The ISO 4217 numeric currency code `amount` is denominated in -- always matches the
  /// `MarketPayment.currency` being refunded.
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

  /// The card the refund was issued back to -- in practice always the same card as the
  /// MarketPayment being refunded, since Stripe refunds are only ever issued back to their
  /// original payment method.
  @$pb.TagNumber(4)
  MarketRefundMethod get method => $_getN(3);
  @$pb.TagNumber(4)
  set method(MarketRefundMethod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasMethod() => $_has(3);
  @$pb.TagNumber(4)
  void clearMethod() => clearField(4);
  @$pb.TagNumber(4)
  MarketRefundMethod ensureMethod() => $_ensure(3);

  /// When this refund was issued.
  @$pb.TagNumber(10)
  $13.Timestamp get createdAt => $_getN(4);
  @$pb.TagNumber(10)
  set createdAt($13.Timestamp v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
  @$pb.TagNumber(10)
  $13.Timestamp ensureCreatedAt() => $_ensure(4);
}

/// Same shape as MarketPaymentMethod -- kept as its own message (rather than reusing
/// MarketPaymentMethod directly) since a MarketRefund and the MarketPayment it refunds are
/// otherwise-independent messages, matching the MarketPayment/MarketRefund split itself.
class MarketRefundMethod extends $pb.GeneratedMessage {
  factory MarketRefundMethod({
    $core.String? cardBrand,
    $core.String? cardLast4,
    $core.int? cardExpMonth,
    $core.int? cardExpYear,
  }) {
    final $result = create();
    if (cardBrand != null) {
      $result.cardBrand = cardBrand;
    }
    if (cardLast4 != null) {
      $result.cardLast4 = cardLast4;
    }
    if (cardExpMonth != null) {
      $result.cardExpMonth = cardExpMonth;
    }
    if (cardExpYear != null) {
      $result.cardExpYear = cardExpYear;
    }
    return $result;
  }
  MarketRefundMethod._() : super();
  factory MarketRefundMethod.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarketRefundMethod.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketRefundMethod', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'cardBrand')
    ..aOS(2, _omitFieldNames ? '' : 'cardLast4')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'cardExpMonth', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'cardExpYear', $pb.PbFieldType.OU3)
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

  /// E.g. "visa", "mastercard", "amex".
  @$pb.TagNumber(1)
  $core.String get cardBrand => $_getSZ(0);
  @$pb.TagNumber(1)
  set cardBrand($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCardBrand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCardBrand() => clearField(1);

  /// Last 4 digits of the card number.
  @$pb.TagNumber(2)
  $core.String get cardLast4 => $_getSZ(1);
  @$pb.TagNumber(2)
  set cardLast4($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCardLast4() => $_has(1);
  @$pb.TagNumber(2)
  void clearCardLast4() => clearField(2);

  /// 1-12.
  @$pb.TagNumber(3)
  $core.int get cardExpMonth => $_getIZ(2);
  @$pb.TagNumber(3)
  set cardExpMonth($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCardExpMonth() => $_has(2);
  @$pb.TagNumber(3)
  void clearCardExpMonth() => clearField(3);

  /// 4-digit year.
  @$pb.TagNumber(4)
  $core.int get cardExpYear => $_getIZ(3);
  @$pb.TagNumber(4)
  set cardExpYear($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCardExpYear() => $_has(3);
  @$pb.TagNumber(4)
  void clearCardExpYear() => clearField(4);
}

/// `MarketPurchase.details`' `PURCHASE_TYPE_MEDIA_STORAGE` variant -- copied verbatim from the
/// originating `MarketProduct.details` at the moment this purchase was fulfilled (see
/// `MarketPurchase.details`' own doc). Field-for-field identical to
/// `MediaStorageSubscriptionDetails` -- kept as its own message only so the Purchase- and
/// Subscription-side `oneof`s stay independent Rust types (see
/// `logic::market_fulfillment::terminate_entitlement`'s own doc for why that distinction matters
/// for `PermissionsAccessPurchaseDetails`/`PermissionsAccessSubscriptionDetails`).
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

  /// The buyer's new total media storage allocation, replacing (not adding to) whatever quota they
  /// already had -- see `logic::market_fulfillment::fulfill_purchase`'s `MediaStorage` arm.
  @$pb.TagNumber(1)
  $fixnum.Int64 get allocationBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set allocationBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllocationBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllocationBytes() => clearField(1);
}

/// `MarketPurchase.details`' `PURCHASE_TYPE_AI_GRANTS` variant -- copied verbatim from the
/// originating `MarketProduct.details` at the moment this purchase was fulfilled. Field-for-field
/// identical to `AIGrantSubscriptionDetails` -- see `MediaStoragePurchaseDetails`'s own doc for why
/// it's still a separate message.
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

  /// Which `AIProvider` this grant is against.
  @$pb.TagNumber(1)
  $core.String get aiProviderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set aiProviderId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAiProviderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAiProviderId() => clearField(1);

  /// Which of that provider's models the grant covers.
  @$pb.TagNumber(2)
  $core.List<$core.String> get modelNames => $_getList(1);

  /// The buyer's new total token balance for `ai_provider_id`/`model_names`, replacing (not adding
  /// to) whatever balance remained -- see `logic::market_fulfillment::fulfill_purchase`'s
  /// `AiGrants` arm.
  @$pb.TagNumber(3)
  $fixnum.Int64 get tokens => $_getI64(2);
  @$pb.TagNumber(3)
  set tokens($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTokens() => clearField(3);
}

/// `MarketPurchase.details`' `PURCHASE_TYPE_RELLM_HOSTING` variant -- unlike the other three
/// `*PurchaseDetails` messages, NOT copied from the originating `MarketProduct.details`; instead
/// built fresh at checkout time from the buyer's own `MakeMarketPurchaseRequest.rellm_hosting_details`
/// (carried through as Stripe Checkout Session metadata -- see `rpcs::market::make_market_purchase`
/// and `web::stripe_webhook::handle_checkout_session_completed`). Field-for-field identical to
/// `RellmHostingSubscriptionDetails` (minus that message's `fulfillment_status`/`fulfillment_notes`) -- see
/// `MediaStoragePurchaseDetails`'s own doc for why it's still a separate message.
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

  /// NOTE: as of the current webhook implementation, the buyer never supplies this and the
  /// originating `MarketProduct`'s own configured size isn't carried through Checkout Session
  /// metadata either, so this is currently always `0` here -- an admin fulfilling an order today
  /// needs to cross-reference the `MarketProduct` itself for the size actually sold. Intended to be
  /// the requested PostgreSQL database size in bytes.
  @$pb.TagNumber(1)
  $fixnum.Int64 get dbSizeBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set dbSizeBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDbSizeBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDbSizeBytes() => clearField(1);

  /// Same caveat as `db_size_bytes` above -- currently always `0`. Intended to be the requested
  /// MinIO (object storage) size in bytes.
  @$pb.TagNumber(2)
  $fixnum.Int64 get minioSizeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set minioSizeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinioSizeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinioSizeBytes() => clearField(2);

  /// The domain the buyer wants their new Rellm instance reachable at (e.g. "myserver.example.com").
  @$pb.TagNumber(3)
  $core.String get domain => $_getSZ(2);
  @$pb.TagNumber(3)
  set domain($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDomain() => $_has(2);
  @$pb.TagNumber(3)
  void clearDomain() => clearField(3);

  /// Where the fulfilling admin should reach the buyer about this order, separate from whatever
  /// email/contact info is on the buyer's own `User` (which may not be checked as often, or may not
  /// exist at all for a server with no email-based signup).
  @$pb.TagNumber(4)
  $core.String get contactEmail => $_getSZ(3);
  @$pb.TagNumber(4)
  set contactEmail($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContactEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearContactEmail() => clearField(4);

  /// Free-form notes from the buyer to the fulfilling admin, captured once at purchase time (e.g.
  /// special requests, existing-data-migration needs). Immutable after purchase -- see
  /// `RellmHostingSubscriptionDetails.additional_information`'s own doc, which carries this same
  /// text forward onto the resulting `MarketSubscription`.
  @$pb.TagNumber(5)
  $core.String get additionalInformation => $_getSZ(4);
  @$pb.TagNumber(5)
  set additionalInformation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalInformation() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalInformation() => clearField(5);
}

/// `MarketPurchase.details`' `PURCHASE_TYPE_PERMISSIONS_ACCESS` variant -- copied verbatim from the
/// originating `MarketProduct.details` at the moment this purchase was fulfilled. Field-for-field
/// identical to `PermissionsAccessSubscriptionDetails`, but kept as a genuinely distinct Rust type
/// (not just documentation) -- see `logic::market_fulfillment::terminate_entitlement`'s own doc,
/// which parses a `MarketSubscription`'s `details` as `PermissionsAccessSubscriptionDetails`
/// specifically (never this message) when clawing back a lapsed grant.
class PermissionsAccessPurchaseDetails extends $pb.GeneratedMessage {
  factory PermissionsAccessPurchaseDetails({
    $core.Iterable<$15.Permission>? permissions,
  }) {
    final $result = create();
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    return $result;
  }
  PermissionsAccessPurchaseDetails._() : super();
  factory PermissionsAccessPurchaseDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PermissionsAccessPurchaseDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PermissionsAccessPurchaseDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<$15.Permission>(1, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PermissionsAccessPurchaseDetails clone() => PermissionsAccessPurchaseDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PermissionsAccessPurchaseDetails copyWith(void Function(PermissionsAccessPurchaseDetails) updates) => super.copyWith((message) => updates(message as PermissionsAccessPurchaseDetails)) as PermissionsAccessPurchaseDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PermissionsAccessPurchaseDetails create() => PermissionsAccessPurchaseDetails._();
  PermissionsAccessPurchaseDetails createEmptyInstance() => create();
  static $pb.PbList<PermissionsAccessPurchaseDetails> createRepeated() => $pb.PbList<PermissionsAccessPurchaseDetails>();
  @$core.pragma('dart2js:noInline')
  static PermissionsAccessPurchaseDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PermissionsAccessPurchaseDetails>(create);
  static PermissionsAccessPurchaseDetails? _defaultInstance;

  /// The permissions this purchase granted -- see `logic::market_fulfillment::fulfill_purchase`'s
  /// `PermissionsAccess` arm (adds these to the buyer's `User.permissions`, union-style).
  @$pb.TagNumber(1)
  $core.List<$15.Permission> get permissions => $_getList(0);
}

enum MarketSubscription_Details {
  mediaStorageSubscriptionDetails, 
  aiGrantSubscriptionDetails, 
  rellmHostingSubscriptionDetails, 
  permissionsAccessSubscriptionDetails, 
  notSet
}

/// Created for *every* `MarketPurchase`, regardless of `MarketProduct.period` -- a recurring
/// (`PURCHASE_PERIOD_ANNUAL`/`PURCHASE_PERIOD_MONTHLY`) one gets re-billed and re-fulfilled
/// automatically every period by `renew_market_subscriptions.rs` until canceled; a
/// `PURCHASE_PERIOD_INDEFINITE` one-time purchase gets a subscription too (with `renews_at` unset --
/// see that field's own doc), purely so it's still cancelable and still carries the same per-type
/// fulfillment tracking (e.g. `RellmHostingSubscriptionDetails.fulfillment_status`/`fulfillment_notes`) every
/// other purchase type gets, even though it never actually bills again.
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
    PermissionsAccessSubscriptionDetails? permissionsAccessSubscriptionDetails,
    $13.Timestamp? createdAt,
    $13.Timestamp? renewsAt,
    $13.Timestamp? canceledAt,
    $13.Timestamp? serviceTerminatedAt,
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
    if (permissionsAccessSubscriptionDetails != null) {
      $result.permissionsAccessSubscriptionDetails = permissionsAccessSubscriptionDetails;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (renewsAt != null) {
      $result.renewsAt = renewsAt;
    }
    if (canceledAt != null) {
      $result.canceledAt = canceledAt;
    }
    if (serviceTerminatedAt != null) {
      $result.serviceTerminatedAt = serviceTerminatedAt;
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
    13 : MarketSubscription_Details.permissionsAccessSubscriptionDetails,
    0 : MarketSubscription_Details.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarketSubscription', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13])
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
    ..aOM<PermissionsAccessSubscriptionDetails>(13, _omitFieldNames ? '' : 'permissionsAccessSubscriptionDetails', subBuilder: PermissionsAccessSubscriptionDetails.create)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(21, _omitFieldNames ? '' : 'renewsAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(22, _omitFieldNames ? '' : 'canceledAt', subBuilder: $13.Timestamp.create)
    ..aOM<$13.Timestamp>(23, _omitFieldNames ? '' : 'serviceTerminatedAt', subBuilder: $13.Timestamp.create)
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

  /// Who owns this subscription (i.e. who's being billed and who the entitlement applies to).
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

  /// What this subscription grants -- copied from (and always matching) `market_product.type`.
  /// Denormalized here the same way `MarketPurchase.type` is -- see that field's own doc.
  @$pb.TagNumber(3)
  PurchaseType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(PurchaseType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => clearField(3);

  /// How often this subscription bills -- copied from `market_product.period` at the time this
  /// subscription was created. `PURCHASE_PERIOD_INDEFINITE` is valid here too (see this message's
  /// own doc) -- it just means `renews_at` stays unset and this subscription never actually bills
  /// again.
  @$pb.TagNumber(4)
  PurchasePeriod get period => $_getN(3);
  @$pb.TagNumber(4)
  set period(PurchasePeriod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPeriod() => $_has(3);
  @$pb.TagNumber(4)
  void clearPeriod() => clearField(4);

  /// The price charged each renewal, in the same unit `MarketProduct.amount` uses -- copied from
  /// `market_product.amount` at the time this subscription was created, so a later price change to
  /// the product doesn't retroactively re-price an existing subscriber.
  @$pb.TagNumber(5)
  $core.int get amount => $_getIZ(4);
  @$pb.TagNumber(5)
  set amount($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAmount() => $_has(4);
  @$pb.TagNumber(5)
  void clearAmount() => clearField(5);

  /// The ISO 4217 numeric currency code `amount` is denominated in -- copied from
  /// `market_product.currency` at the time this subscription was created.
  @$pb.TagNumber(6)
  $core.int get currency => $_getIZ(5);
  @$pb.TagNumber(6)
  set currency($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCurrency() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrency() => clearField(6);

  /// The `MarketProduct` this subscription was made against, as it existed at the time it was
  /// fetched -- may since have changed price/details/been delisted (delisting an already-subscribed
  /// product doesn't cancel existing subscriptions, only blocks new purchases). Note: marshaling
  /// should handle the circular relationship here gracefully.
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

  /// Every `MarketPurchase` billed against this subscription so far -- the original purchase plus
  /// every successful renewal charge, newest first. Each entry's own `market_subscription` field is
  /// left unset here (see `MarketPurchase.market_subscription`'s own doc) to avoid recursing back
  /// into this same subscription.
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

  @$pb.TagNumber(13)
  PermissionsAccessSubscriptionDetails get permissionsAccessSubscriptionDetails => $_getN(11);
  @$pb.TagNumber(13)
  set permissionsAccessSubscriptionDetails(PermissionsAccessSubscriptionDetails v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasPermissionsAccessSubscriptionDetails() => $_has(11);
  @$pb.TagNumber(13)
  void clearPermissionsAccessSubscriptionDetails() => clearField(13);
  @$pb.TagNumber(13)
  PermissionsAccessSubscriptionDetails ensurePermissionsAccessSubscriptionDetails() => $_ensure(11);

  /// When this subscription was first created (i.e. when the initial `MarketPurchase` was
  /// fulfilled).
  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(12);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(12);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(12);

  /// When the next renewal charge is due. Always unset for a `PURCHASE_PERIOD_INDEFINITE`
  /// subscription (see this message's own doc) -- there is no next charge. Otherwise, advanced by
  /// one `period` on every successful renewal (`renew_market_subscriptions.rs`); left untouched
  /// once `canceled_at` is set, since a canceled subscription never renews again regardless of what
  /// this still says.
  @$pb.TagNumber(21)
  $13.Timestamp get renewsAt => $_getN(13);
  @$pb.TagNumber(21)
  set renewsAt($13.Timestamp v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasRenewsAt() => $_has(13);
  @$pb.TagNumber(21)
  void clearRenewsAt() => clearField(21);
  @$pb.TagNumber(21)
  $13.Timestamp ensureRenewsAt() => $_ensure(13);

  /// Set once the subscription will no longer renew -- either the buyer/admin explicitly canceled it
  /// (CancelMarketSubscription) or a renewal charge failed. The subscription's entitlement (media
  /// storage quota, granted permissions, etc.) stays active until whichever is later of
  /// renews_at/canceled_at, at which point renew_market_subscriptions.rs revokes it and sets
  /// service_terminated_at. Also the moment `MarketProduct.sold_count` is decremented, freeing this
  /// subscription's slot for a new buyer (see that field's own doc).
  @$pb.TagNumber(22)
  $13.Timestamp get canceledAt => $_getN(14);
  @$pb.TagNumber(22)
  set canceledAt($13.Timestamp v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasCanceledAt() => $_has(14);
  @$pb.TagNumber(22)
  void clearCanceledAt() => clearField(22);
  @$pb.TagNumber(22)
  $13.Timestamp ensureCanceledAt() => $_ensure(14);

  /// The time permissions were removed, media storage quotas reset, etc. -- i.e. when
  /// `logic::market_fulfillment::terminate_entitlement` actually ran for this subscription. Always
  /// unset while `canceled_at` is unset; may remain unset for a while *after* `canceled_at` is set,
  /// since the entitlement intentionally stays active until the later of `renews_at`/`canceled_at`
  /// (see `canceled_at`'s own doc) -- a buyer who cancels mid-period keeps what they already paid
  /// for through the end of that period.
  @$pb.TagNumber(23)
  $13.Timestamp get serviceTerminatedAt => $_getN(15);
  @$pb.TagNumber(23)
  set serviceTerminatedAt($13.Timestamp v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasServiceTerminatedAt() => $_has(15);
  @$pb.TagNumber(23)
  void clearServiceTerminatedAt() => clearField(23);
  @$pb.TagNumber(23)
  $13.Timestamp ensureServiceTerminatedAt() => $_ensure(15);
}

/// `MarketProduct.details`/`MarketSubscription.details`' `PURCHASE_TYPE_MEDIA_STORAGE` variant --
/// what a media storage product actually grants. Field-for-field identical to
/// `MediaStoragePurchaseDetails` -- see that message's own doc for why it's still a distinct type.
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

  /// How much media storage this product/subscription grants the buyer, replacing (not adding to)
  /// whatever quota they already had -- see `logic::market_fulfillment::fulfill_purchase`'s
  /// `MediaStorage` arm.
  @$pb.TagNumber(1)
  $fixnum.Int64 get allocationBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set allocationBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAllocationBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearAllocationBytes() => clearField(1);
}

/// `MarketProduct.details`/`MarketSubscription.details`' `PURCHASE_TYPE_AI_GRANTS` variant -- what
/// an AI token product actually grants. Field-for-field identical to `AIGrantPurchaseDetails` --
/// see that message's own doc for why it's still a distinct type.
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

  /// Which `AIProvider` this grant is against.
  @$pb.TagNumber(1)
  $core.String get aiProviderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set aiProviderId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAiProviderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAiProviderId() => clearField(1);

  /// Which of that provider's models the grant covers.
  @$pb.TagNumber(2)
  $core.List<$core.String> get modelNames => $_getList(1);

  /// How many tokens this product/subscription grants the buyer each time it's (re-)fulfilled,
  /// replacing (not adding to) whatever balance remained -- see
  /// `logic::market_fulfillment::fulfill_purchase`'s `AiGrants` arm.
  @$pb.TagNumber(3)
  $fixnum.Int64 get tokens => $_getI64(2);
  @$pb.TagNumber(3)
  set tokens($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTokens() => clearField(3);
}

/// `MarketProduct.details`/`MarketSubscription.details`' `PURCHASE_TYPE_RELLM_HOSTING` variant --
/// what a dedicated-hosting product actually grants, plus the buyer's own request details and the
/// admin's own fulfillment tracking for it. Field-for-field identical to `RellmHostingPurchaseDetails`
/// for the first five fields (see that message's own doc); `fulfillment_status`/`fulfillment_notes` below have
/// no `*PurchaseDetails` counterpart, since they're only ever meaningful on the standing
/// `MarketSubscription`, not on any one individual `MarketPurchase` billing event.
class RellmHostingSubscriptionDetails extends $pb.GeneratedMessage {
  factory RellmHostingSubscriptionDetails({
    $fixnum.Int64? dbSizeBytes,
    $fixnum.Int64? minioSizeBytes,
    $core.String? domain,
    $core.String? contactEmail,
    $core.String? additionalInformation,
    FulfillmentStatus? fulfillmentStatus,
    $core.Iterable<FulfillmentNote>? fulfillmentNotes,
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
    if (fulfillmentStatus != null) {
      $result.fulfillmentStatus = fulfillmentStatus;
    }
    if (fulfillmentNotes != null) {
      $result.fulfillmentNotes.addAll(fulfillmentNotes);
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
    ..e<FulfillmentStatus>(6, _omitFieldNames ? '' : 'fulfillmentStatus', $pb.PbFieldType.OE, defaultOrMaker: FulfillmentStatus.FULFILLMENT_STATUS_AWAITING_HOST_ADMIN, valueOf: FulfillmentStatus.valueOf, enumValues: FulfillmentStatus.values)
    ..pc<FulfillmentNote>(7, _omitFieldNames ? '' : 'fulfillmentNotes', $pb.PbFieldType.PM, subBuilder: FulfillmentNote.create)
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

  /// On a `MarketProduct`: the PostgreSQL database size (in bytes) this product is configured to
  /// provision. On a `MarketSubscription`: see `RellmHostingPurchaseDetails.db_size_bytes`'s own
  /// doc -- as of the current webhook implementation, this is currently always `0` here too, since
  /// the subscription's `details` is built the same way the purchase's is.
  @$pb.TagNumber(1)
  $fixnum.Int64 get dbSizeBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set dbSizeBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDbSizeBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDbSizeBytes() => clearField(1);

  /// Same caveat as `db_size_bytes` above. On a `MarketProduct`: the MinIO (object storage) size (in
  /// bytes) this product is configured to provision.
  @$pb.TagNumber(2)
  $fixnum.Int64 get minioSizeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set minioSizeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinioSizeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinioSizeBytes() => clearField(2);

  /// On a `MarketProduct`: unset/meaningless (a product isn't tied to any one domain). On a
  /// `MarketSubscription`: the domain the buyer wants their new Rellm instance reachable at, from
  /// `RellmHostingPurchaseDetails.domain`.
  @$pb.TagNumber(3)
  $core.String get domain => $_getSZ(2);
  @$pb.TagNumber(3)
  set domain($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDomain() => $_has(2);
  @$pb.TagNumber(3)
  void clearDomain() => clearField(3);

  /// On a `MarketProduct`: unset/meaningless. On a `MarketSubscription`: where the fulfilling admin
  /// should reach the buyer about this order, from `RellmHostingPurchaseDetails.contact_email`.
  @$pb.TagNumber(4)
  $core.String get contactEmail => $_getSZ(3);
  @$pb.TagNumber(4)
  set contactEmail($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContactEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearContactEmail() => clearField(4);

  /// Immutable after purchase -- the buyer's own notes to the admin fulfilling this order. Never
  /// editable via UpdateMarketSubscription (see that RPC's own doc); `fulfillment_notes` below is
  /// the admin/buyer conversation about fulfilling it.
  @$pb.TagNumber(5)
  $core.String get additionalInformation => $_getSZ(4);
  @$pb.TagNumber(5)
  set additionalInformation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalInformation() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalInformation() => clearField(5);

  /// Where this Rellm hosting order currently stands -- Rellm hosting is deliberately not automated
  /// (see `market.proto`'s own top-of-file notes and `logic::market_fulfillment::fulfill_purchase`'s
  /// `RellmHosting` no-op arm), so this is the one manual "how far along is this order" signal,
  /// shown on `/market/fulfillment` (`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`).
  /// Never independently settable by a client -- always server-derived as whatever
  /// `fulfillment_notes`' own last entry's `fulfillment_status` says (or
  /// `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` if `fulfillment_notes` is empty), so this field can
  /// never drift out of sync with the history that explains *why* it's in that state.
  @$pb.TagNumber(6)
  FulfillmentStatus get fulfillmentStatus => $_getN(5);
  @$pb.TagNumber(6)
  set fulfillmentStatus(FulfillmentStatus v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasFulfillmentStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearFulfillmentStatus() => clearField(6);

  /// The admin/buyer conversation about fulfilling this order -- oldest to newest, append-only (see
  /// `UpdateMarketSubscription`'s own doc: a new entry can only ever be appended after whatever's
  /// already here, never inserted/reordered/removed, and its `user_id` must match whoever's actually
  /// making the request -- the server stamps `created_at` itself).
  @$pb.TagNumber(7)
  $core.List<FulfillmentNote> get fulfillmentNotes => $_getList(6);
}

/// One entry in a MarketSubscription's `fulfillment_notes` -- see that field's own doc. Immutable
/// once appended: `UpdateMarketSubscription` only ever accepts a `fulfillment_notes` list whose
/// existing entries are byte-for-byte identical to what's already stored (see that RPC's own doc).
class FulfillmentNote extends $pb.GeneratedMessage {
  factory FulfillmentNote({
    $core.String? userId,
    $core.String? note,
    FulfillmentStatus? fulfillmentStatus,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (note != null) {
      $result.note = note;
    }
    if (fulfillmentStatus != null) {
      $result.fulfillmentStatus = fulfillmentStatus;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  FulfillmentNote._() : super();
  factory FulfillmentNote.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FulfillmentNote.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FulfillmentNote', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'note')
    ..e<FulfillmentStatus>(3, _omitFieldNames ? '' : 'fulfillmentStatus', $pb.PbFieldType.OE, defaultOrMaker: FulfillmentStatus.FULFILLMENT_STATUS_AWAITING_HOST_ADMIN, valueOf: FulfillmentStatus.valueOf, enumValues: FulfillmentStatus.values)
    ..aOM<$13.Timestamp>(4, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FulfillmentNote clone() => FulfillmentNote()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FulfillmentNote copyWith(void Function(FulfillmentNote) updates) => super.copyWith((message) => updates(message as FulfillmentNote)) as FulfillmentNote;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FulfillmentNote create() => FulfillmentNote._();
  FulfillmentNote createEmptyInstance() => create();
  static $pb.PbList<FulfillmentNote> createRepeated() => $pb.PbList<FulfillmentNote>();
  @$core.pragma('dart2js:noInline')
  static FulfillmentNote getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FulfillmentNote>(create);
  static FulfillmentNote? _defaultInstance;

  /// Whoever wrote this note -- either the fulfilling admin or the buyer themselves, depending on
  /// which side of the conversation this entry is. Must match the id of whoever's actually making
  /// the `UpdateMarketSubscription` request that appends this entry (server-validated -- see that
  /// RPC's own doc); a client can't author a note on someone else's behalf.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The note's own text -- required (rejected with `fulfillment_note_text_required`) unless this
  /// entry also changes `fulfillment_status` from whatever the previous entry (or, for the very
  /// first note, the implicit `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` default) left it at, in which
  /// case an admin can record a bare status change with no accompanying text (e.g. the automatic
  /// "admin opened this order" transition to `FULFILLMENT_STATUS_IN_PROGRESS` -- see that enum
  /// value's own doc).
  @$pb.TagNumber(2)
  $core.String get note => $_getSZ(1);
  @$pb.TagNumber(2)
  set note($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNote() => $_has(1);
  @$pb.TagNumber(2)
  void clearNote() => clearField(2);

  /// What `RellmHostingSubscriptionDetails.fulfillment_status` became as of this note -- unchanged
  /// from the previous entry for a plain note, or the new value for an actual status transition (see
  /// `note`'s own doc on when text is/isn't required for each case). This is what makes
  /// `fulfillment_notes` a genuine "fulfillment state history," not just a chat log alongside a
  /// separately-tracked current status.
  @$pb.TagNumber(3)
  FulfillmentStatus get fulfillmentStatus => $_getN(2);
  @$pb.TagNumber(3)
  set fulfillmentStatus(FulfillmentStatus v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFulfillmentStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearFulfillmentStatus() => clearField(3);

  /// When this note was added. Server-stamped -- `UpdateMarketSubscription` always ignores whatever
  /// timestamp the client sends for a newly-appended entry.
  @$pb.TagNumber(4)
  $13.Timestamp get createdAt => $_getN(3);
  @$pb.TagNumber(4)
  set createdAt($13.Timestamp v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatedAt() => clearField(4);
  @$pb.TagNumber(4)
  $13.Timestamp ensureCreatedAt() => $_ensure(3);
}

/// `MarketProduct.details`/`MarketSubscription.details`' `PURCHASE_TYPE_PERMISSIONS_ACCESS`
/// variant -- what a permissions-bundle product actually grants. Field-for-field identical to
/// `PermissionsAccessPurchaseDetails` -- see that message's own doc for why it's still a distinct
/// type (that distinction is exactly what lets `logic::market_fulfillment::terminate_entitlement`
/// tell "what to claw back" apart from "what was originally billed").
class PermissionsAccessSubscriptionDetails extends $pb.GeneratedMessage {
  factory PermissionsAccessSubscriptionDetails({
    $core.Iterable<$15.Permission>? permissions,
  }) {
    final $result = create();
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    return $result;
  }
  PermissionsAccessSubscriptionDetails._() : super();
  factory PermissionsAccessSubscriptionDetails.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PermissionsAccessSubscriptionDetails.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PermissionsAccessSubscriptionDetails', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<$15.Permission>(1, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $15.Permission.valueOf, enumValues: $15.Permission.values, defaultEnumValue: $15.Permission.PERMISSION_UNKNOWN)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PermissionsAccessSubscriptionDetails clone() => PermissionsAccessSubscriptionDetails()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PermissionsAccessSubscriptionDetails copyWith(void Function(PermissionsAccessSubscriptionDetails) updates) => super.copyWith((message) => updates(message as PermissionsAccessSubscriptionDetails)) as PermissionsAccessSubscriptionDetails;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PermissionsAccessSubscriptionDetails create() => PermissionsAccessSubscriptionDetails._();
  PermissionsAccessSubscriptionDetails createEmptyInstance() => create();
  static $pb.PbList<PermissionsAccessSubscriptionDetails> createRepeated() => $pb.PbList<PermissionsAccessSubscriptionDetails>();
  @$core.pragma('dart2js:noInline')
  static PermissionsAccessSubscriptionDetails getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PermissionsAccessSubscriptionDetails>(create);
  static PermissionsAccessSubscriptionDetails? _defaultInstance;

  /// Which `Permission`s this product/subscription grants the buyer -- see
  /// `logic::market_fulfillment::fulfill_purchase`'s `PermissionsAccess` arm (union-added to the
  /// buyer's own `User.permissions`, never replacing what they already had) and
  /// `terminate_entitlement`'s own arm (the exact claw-back set on cancellation/expiry).
  /// Intentionally excludes permissions dangerous or nonsensical to sell this way -- e.g.
  /// "Grant Basic Permissions," any "Moderate"/"Read All System Messages" permission, "Admin,"
  /// "View Private Contact Methods," and "Edit Cluster Settings" must never appear in a Market
  /// product's own `permissions` list. Enforced server-side on `CreateMarketProduct`/
  /// `UpdateMarketProduct` (rejected with `permission_not_purchasable`) and again on
  /// `MakeMarketPurchase` (defense in depth, in case a permission is later removed from the
  /// purchasable set after a product granting it already exists) -- see
  /// `rpcs::market::create_market_product::PURCHASABLE_PERMISSIONS`. NOTE: that Rust list is an
  /// explicit include-list, not an exclude-list -- described here as an exclusion for readability,
  /// but implemented as "only these permissions are purchasable" so a newly-added `Permission` is
  /// never purchasable by default; it has to be deliberately added to that list.
  @$pb.TagNumber(1)
  $core.List<$15.Permission> get permissions => $_getList(0);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
