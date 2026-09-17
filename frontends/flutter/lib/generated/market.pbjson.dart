//
//  Generated code. Do not modify.
//  source: market.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use purchaseTypeDescriptor instead')
const PurchaseType$json = {
  '1': 'PurchaseType',
  '2': [
    {'1': 'PURCHASE_TYPE_MEDIA_STORAGE', '2': 0},
    {'1': 'PURCHASE_TYPE_AI_GRANTS', '2': 1},
    {'1': 'PURCHASE_TYPE_RELLM_HOSTING', '2': 2},
    {'1': 'PURCHASE_TYPE_PERMISSIONS_ACCESS', '2': 3},
  ],
};

/// Descriptor for `PurchaseType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List purchaseTypeDescriptor = $convert.base64Decode(
    'CgxQdXJjaGFzZVR5cGUSHwobUFVSQ0hBU0VfVFlQRV9NRURJQV9TVE9SQUdFEAASGwoXUFVSQ0'
    'hBU0VfVFlQRV9BSV9HUkFOVFMQARIfChtQVVJDSEFTRV9UWVBFX1JFTExNX0hPU1RJTkcQAhIk'
    'CiBQVVJDSEFTRV9UWVBFX1BFUk1JU1NJT05TX0FDQ0VTUxAD');

@$core.Deprecated('Use purchasePeriodDescriptor instead')
const PurchasePeriod$json = {
  '1': 'PurchasePeriod',
  '2': [
    {'1': 'PURCHASE_PERIOD_INDEFINITE', '2': 0},
    {'1': 'PURCHASE_PERIOD_ANNUAL', '2': 1},
    {'1': 'PURCHASE_PERIOD_MONTHLY', '2': 2},
  ],
};

/// Descriptor for `PurchasePeriod`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List purchasePeriodDescriptor = $convert.base64Decode(
    'Cg5QdXJjaGFzZVBlcmlvZBIeChpQVVJDSEFTRV9QRVJJT0RfSU5ERUZJTklURRAAEhoKFlBVUk'
    'NIQVNFX1BFUklPRF9BTk5VQUwQARIbChdQVVJDSEFTRV9QRVJJT0RfTU9OVEhMWRAC');

@$core.Deprecated('Use getMarketSubscriptionsRequestTypeDescriptor instead')
const GetMarketSubscriptionsRequestType$json = {
  '1': 'GetMarketSubscriptionsRequestType',
  '2': [
    {'1': 'GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE', '2': 0},
    {'1': 'GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN', '2': 1},
  ],
};

/// Descriptor for `GetMarketSubscriptionsRequestType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List getMarketSubscriptionsRequestTypeDescriptor = $convert.base64Decode(
    'CiFHZXRNYXJrZXRTdWJzY3JpcHRpb25zUmVxdWVzdFR5cGUSMQotR0VUX01BUktFVF9TVUJTQ1'
    'JJUFRJT05TX1JFUVVFU1RfRk9SX1BVUkNIQVNFEAASOgo2R0VUX01BUktFVF9TVUJTQ1JJUFRJ'
    'T05TX1JFUVVFU1RfRk9SX0ZVTEZJTExNRU5UX0FETUlOEAE=');

@$core.Deprecated('Use marketProductDescriptor instead')
const MarketProduct$json = {
  '1': 'MarketProduct',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.rellm.PurchaseType', '10': 'type'},
    {'1': 'period', '3': 3, '4': 1, '5': 14, '6': '.rellm.PurchasePeriod', '10': 'period'},
    {'1': 'amount', '3': 4, '4': 1, '5': 13, '10': 'amount'},
    {'1': 'currency', '3': 5, '4': 1, '5': 13, '10': 'currency'},
    {'1': 'available_count', '3': 6, '4': 1, '5': 13, '10': 'availableCount'},
    {'1': 'sold_count', '3': 7, '4': 1, '5': 13, '10': 'soldCount'},
    {'1': 'media_storage_subscription_details', '3': 10, '4': 1, '5': 11, '6': '.rellm.MediaStorageSubscriptionDetails', '9': 0, '10': 'mediaStorageSubscriptionDetails'},
    {'1': 'ai_grant_subscription_details', '3': 11, '4': 1, '5': 11, '6': '.rellm.AIGrantSubscriptionDetails', '9': 0, '10': 'aiGrantSubscriptionDetails'},
    {'1': 'rellm_hosting_subscription_details', '3': 12, '4': 1, '5': 11, '6': '.rellm.RellmHostingSubscriptionDetails', '9': 0, '10': 'rellmHostingSubscriptionDetails'},
    {'1': 'permissions_access_subscription_details', '3': 13, '4': 1, '5': 11, '6': '.rellm.PermissionsAccessSubscriptionDetails', '9': 0, '10': 'permissionsAccessSubscriptionDetails'},
    {'1': 'created_at', '3': 20, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'delisted_at', '3': 21, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'delistedAt', '17': true},
  ],
  '8': [
    {'1': 'details'},
    {'1': '_delisted_at'},
  ],
};

/// Descriptor for `MarketProduct`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketProductDescriptor = $convert.base64Decode(
    'Cg1NYXJrZXRQcm9kdWN0Eg4KAmlkGAEgASgJUgJpZBInCgR0eXBlGAIgASgOMhMucmVsbG0uUH'
    'VyY2hhc2VUeXBlUgR0eXBlEi0KBnBlcmlvZBgDIAEoDjIVLnJlbGxtLlB1cmNoYXNlUGVyaW9k'
    'UgZwZXJpb2QSFgoGYW1vdW50GAQgASgNUgZhbW91bnQSGgoIY3VycmVuY3kYBSABKA1SCGN1cn'
    'JlbmN5EicKD2F2YWlsYWJsZV9jb3VudBgGIAEoDVIOYXZhaWxhYmxlQ291bnQSHQoKc29sZF9j'
    'b3VudBgHIAEoDVIJc29sZENvdW50EnUKIm1lZGlhX3N0b3JhZ2Vfc3Vic2NyaXB0aW9uX2RldG'
    'FpbHMYCiABKAsyJi5yZWxsbS5NZWRpYVN0b3JhZ2VTdWJzY3JpcHRpb25EZXRhaWxzSABSH21l'
    'ZGlhU3RvcmFnZVN1YnNjcmlwdGlvbkRldGFpbHMSZgodYWlfZ3JhbnRfc3Vic2NyaXB0aW9uX2'
    'RldGFpbHMYCyABKAsyIS5yZWxsbS5BSUdyYW50U3Vic2NyaXB0aW9uRGV0YWlsc0gAUhphaUdy'
    'YW50U3Vic2NyaXB0aW9uRGV0YWlscxJ1CiJyZWxsbV9ob3N0aW5nX3N1YnNjcmlwdGlvbl9kZX'
    'RhaWxzGAwgASgLMiYucmVsbG0uUmVsbG1Ib3N0aW5nU3Vic2NyaXB0aW9uRGV0YWlsc0gAUh9y'
    'ZWxsbUhvc3RpbmdTdWJzY3JpcHRpb25EZXRhaWxzEoQBCidwZXJtaXNzaW9uc19hY2Nlc3Nfc3'
    'Vic2NyaXB0aW9uX2RldGFpbHMYDSABKAsyKy5yZWxsbS5QZXJtaXNzaW9uc0FjY2Vzc1N1YnNj'
    'cmlwdGlvbkRldGFpbHNIAFIkcGVybWlzc2lvbnNBY2Nlc3NTdWJzY3JpcHRpb25EZXRhaWxzEj'
    'kKCmNyZWF0ZWRfYXQYFCABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVk'
    'QXQSQAoLZGVsaXN0ZWRfYXQYFSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wSAFSCm'
    'RlbGlzdGVkQXSIAQFCCQoHZGV0YWlsc0IOCgxfZGVsaXN0ZWRfYXQ=');

@$core.Deprecated('Use getMarketProductsRequestDescriptor instead')
const GetMarketProductsRequest$json = {
  '1': 'GetMarketProductsRequest',
};

/// Descriptor for `GetMarketProductsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMarketProductsRequestDescriptor = $convert.base64Decode(
    'ChhHZXRNYXJrZXRQcm9kdWN0c1JlcXVlc3Q=');

@$core.Deprecated('Use getMarketProductsResponseDescriptor instead')
const GetMarketProductsResponse$json = {
  '1': 'GetMarketProductsResponse',
  '2': [
    {'1': 'market_products', '3': 1, '4': 3, '5': 11, '6': '.rellm.MarketProduct', '10': 'marketProducts'},
  ],
};

/// Descriptor for `GetMarketProductsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMarketProductsResponseDescriptor = $convert.base64Decode(
    'ChlHZXRNYXJrZXRQcm9kdWN0c1Jlc3BvbnNlEj0KD21hcmtldF9wcm9kdWN0cxgBIAMoCzIULn'
    'JlbGxtLk1hcmtldFByb2R1Y3RSDm1hcmtldFByb2R1Y3Rz');

@$core.Deprecated('Use getMarketSubscriptionsRequestDescriptor instead')
const GetMarketSubscriptionsRequest$json = {
  '1': 'GetMarketSubscriptionsRequest',
  '2': [
    {'1': 'request_type', '3': 1, '4': 1, '5': 14, '6': '.rellm.GetMarketSubscriptionsRequestType', '10': 'requestType'},
  ],
};

/// Descriptor for `GetMarketSubscriptionsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMarketSubscriptionsRequestDescriptor = $convert.base64Decode(
    'Ch1HZXRNYXJrZXRTdWJzY3JpcHRpb25zUmVxdWVzdBJLCgxyZXF1ZXN0X3R5cGUYASABKA4yKC'
    '5yZWxsbS5HZXRNYXJrZXRTdWJzY3JpcHRpb25zUmVxdWVzdFR5cGVSC3JlcXVlc3RUeXBl');

@$core.Deprecated('Use getMarketSubscriptionsResponseDescriptor instead')
const GetMarketSubscriptionsResponse$json = {
  '1': 'GetMarketSubscriptionsResponse',
  '2': [
    {'1': 'market_subscriptions', '3': 1, '4': 3, '5': 11, '6': '.rellm.MarketSubscription', '10': 'marketSubscriptions'},
  ],
};

/// Descriptor for `GetMarketSubscriptionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMarketSubscriptionsResponseDescriptor = $convert.base64Decode(
    'Ch5HZXRNYXJrZXRTdWJzY3JpcHRpb25zUmVzcG9uc2USTAoUbWFya2V0X3N1YnNjcmlwdGlvbn'
    'MYASADKAsyGS5yZWxsbS5NYXJrZXRTdWJzY3JpcHRpb25SE21hcmtldFN1YnNjcmlwdGlvbnM=');

@$core.Deprecated('Use makeMarketPurchaseRequestDescriptor instead')
const MakeMarketPurchaseRequest$json = {
  '1': 'MakeMarketPurchaseRequest',
  '2': [
    {'1': 'market_product_id', '3': 1, '4': 1, '5': 9, '10': 'marketProductId'},
    {'1': 'rellm_hosting_details', '3': 2, '4': 1, '5': 11, '6': '.rellm.RellmHostingPurchaseDetails', '9': 0, '10': 'rellmHostingDetails', '17': true},
  ],
  '8': [
    {'1': '_rellm_hosting_details'},
  ],
};

/// Descriptor for `MakeMarketPurchaseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List makeMarketPurchaseRequestDescriptor = $convert.base64Decode(
    'ChlNYWtlTWFya2V0UHVyY2hhc2VSZXF1ZXN0EioKEW1hcmtldF9wcm9kdWN0X2lkGAEgASgJUg'
    '9tYXJrZXRQcm9kdWN0SWQSWwoVcmVsbG1faG9zdGluZ19kZXRhaWxzGAIgASgLMiIucmVsbG0u'
    'UmVsbG1Ib3N0aW5nUHVyY2hhc2VEZXRhaWxzSABSE3JlbGxtSG9zdGluZ0RldGFpbHOIAQFCGA'
    'oWX3JlbGxtX2hvc3RpbmdfZGV0YWlscw==');

@$core.Deprecated('Use makeMarketPurchaseResponseDescriptor instead')
const MakeMarketPurchaseResponse$json = {
  '1': 'MakeMarketPurchaseResponse',
  '2': [
    {'1': 'checkout_url', '3': 1, '4': 1, '5': 9, '10': 'checkoutUrl'},
  ],
};

/// Descriptor for `MakeMarketPurchaseResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List makeMarketPurchaseResponseDescriptor = $convert.base64Decode(
    'ChpNYWtlTWFya2V0UHVyY2hhc2VSZXNwb25zZRIhCgxjaGVja291dF91cmwYASABKAlSC2NoZW'
    'Nrb3V0VXJs');

@$core.Deprecated('Use marketPurchaseDescriptor instead')
const MarketPurchase$json = {
  '1': 'MarketPurchase',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'buyer', '3': 2, '4': 1, '5': 11, '6': '.rellm.Author', '10': 'buyer'},
    {'1': 'type', '3': 3, '4': 1, '5': 14, '6': '.rellm.PurchaseType', '10': 'type'},
    {'1': 'market_product', '3': 4, '4': 1, '5': 11, '6': '.rellm.MarketProduct', '10': 'marketProduct'},
    {'1': 'market_subscription', '3': 5, '4': 1, '5': 11, '6': '.rellm.MarketSubscription', '9': 1, '10': 'marketSubscription', '17': true},
    {'1': 'market_payments', '3': 6, '4': 3, '5': 11, '6': '.rellm.MarketPayment', '10': 'marketPayments'},
    {'1': 'market_refunds', '3': 7, '4': 3, '5': 11, '6': '.rellm.MarketRefund', '10': 'marketRefunds'},
    {'1': 'media_storage_purchase_details', '3': 10, '4': 1, '5': 11, '6': '.rellm.MediaStoragePurchaseDetails', '9': 0, '10': 'mediaStoragePurchaseDetails'},
    {'1': 'ai_grant_purchase_details', '3': 11, '4': 1, '5': 11, '6': '.rellm.AIGrantPurchaseDetails', '9': 0, '10': 'aiGrantPurchaseDetails'},
    {'1': 'rellm_hosting_purchase_details', '3': 12, '4': 1, '5': 11, '6': '.rellm.RellmHostingPurchaseDetails', '9': 0, '10': 'rellmHostingPurchaseDetails'},
    {'1': 'permissions_access_purchase_details', '3': 13, '4': 1, '5': 11, '6': '.rellm.PermissionsAccessPurchaseDetails', '9': 0, '10': 'permissionsAccessPurchaseDetails'},
    {'1': 'created_at', '3': 20, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
  ],
  '8': [
    {'1': 'details'},
    {'1': '_market_subscription'},
  ],
};

/// Descriptor for `MarketPurchase`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketPurchaseDescriptor = $convert.base64Decode(
    'Cg5NYXJrZXRQdXJjaGFzZRIOCgJpZBgBIAEoCVICaWQSIwoFYnV5ZXIYAiABKAsyDS5yZWxsbS'
    '5BdXRob3JSBWJ1eWVyEicKBHR5cGUYAyABKA4yEy5yZWxsbS5QdXJjaGFzZVR5cGVSBHR5cGUS'
    'OwoObWFya2V0X3Byb2R1Y3QYBCABKAsyFC5yZWxsbS5NYXJrZXRQcm9kdWN0Ug1tYXJrZXRQcm'
    '9kdWN0Ek8KE21hcmtldF9zdWJzY3JpcHRpb24YBSABKAsyGS5yZWxsbS5NYXJrZXRTdWJzY3Jp'
    'cHRpb25IAVISbWFya2V0U3Vic2NyaXB0aW9uiAEBEj0KD21hcmtldF9wYXltZW50cxgGIAMoCz'
    'IULnJlbGxtLk1hcmtldFBheW1lbnRSDm1hcmtldFBheW1lbnRzEjoKDm1hcmtldF9yZWZ1bmRz'
    'GAcgAygLMhMucmVsbG0uTWFya2V0UmVmdW5kUg1tYXJrZXRSZWZ1bmRzEmkKHm1lZGlhX3N0b3'
    'JhZ2VfcHVyY2hhc2VfZGV0YWlscxgKIAEoCzIiLnJlbGxtLk1lZGlhU3RvcmFnZVB1cmNoYXNl'
    'RGV0YWlsc0gAUhttZWRpYVN0b3JhZ2VQdXJjaGFzZURldGFpbHMSWgoZYWlfZ3JhbnRfcHVyY2'
    'hhc2VfZGV0YWlscxgLIAEoCzIdLnJlbGxtLkFJR3JhbnRQdXJjaGFzZURldGFpbHNIAFIWYWlH'
    'cmFudFB1cmNoYXNlRGV0YWlscxJpCh5yZWxsbV9ob3N0aW5nX3B1cmNoYXNlX2RldGFpbHMYDC'
    'ABKAsyIi5yZWxsbS5SZWxsbUhvc3RpbmdQdXJjaGFzZURldGFpbHNIAFIbcmVsbG1Ib3N0aW5n'
    'UHVyY2hhc2VEZXRhaWxzEngKI3Blcm1pc3Npb25zX2FjY2Vzc19wdXJjaGFzZV9kZXRhaWxzGA'
    '0gASgLMicucmVsbG0uUGVybWlzc2lvbnNBY2Nlc3NQdXJjaGFzZURldGFpbHNIAFIgcGVybWlz'
    'c2lvbnNBY2Nlc3NQdXJjaGFzZURldGFpbHMSOQoKY3JlYXRlZF9hdBgUIAEoCzIaLmdvb2dsZS'
    '5wcm90b2J1Zi5UaW1lc3RhbXBSCWNyZWF0ZWRBdEIJCgdkZXRhaWxzQhYKFF9tYXJrZXRfc3Vi'
    'c2NyaXB0aW9u');

@$core.Deprecated('Use marketPaymentDescriptor instead')
const MarketPayment$json = {
  '1': 'MarketPayment',
  '2': [
    {'1': 'amount', '3': 1, '4': 1, '5': 13, '10': 'amount'},
    {'1': 'currency', '3': 2, '4': 1, '5': 13, '10': 'currency'},
    {'1': 'market_purchase_id', '3': 3, '4': 1, '5': 9, '10': 'marketPurchaseId'},
    {'1': 'method', '3': 4, '4': 1, '5': 11, '6': '.rellm.MarketPaymentMethod', '9': 0, '10': 'method', '17': true},
    {'1': 'created_at', '3': 10, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
  ],
  '8': [
    {'1': '_method'},
  ],
};

/// Descriptor for `MarketPayment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketPaymentDescriptor = $convert.base64Decode(
    'Cg1NYXJrZXRQYXltZW50EhYKBmFtb3VudBgBIAEoDVIGYW1vdW50EhoKCGN1cnJlbmN5GAIgAS'
    'gNUghjdXJyZW5jeRIsChJtYXJrZXRfcHVyY2hhc2VfaWQYAyABKAlSEG1hcmtldFB1cmNoYXNl'
    'SWQSNwoGbWV0aG9kGAQgASgLMhoucmVsbG0uTWFya2V0UGF5bWVudE1ldGhvZEgAUgZtZXRob2'
    'SIAQESOQoKY3JlYXRlZF9hdBgKIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWNy'
    'ZWF0ZWRBdEIJCgdfbWV0aG9k');

@$core.Deprecated('Use marketPaymentMethodDescriptor instead')
const MarketPaymentMethod$json = {
  '1': 'MarketPaymentMethod',
  '2': [
    {'1': 'card_brand', '3': 1, '4': 1, '5': 9, '10': 'cardBrand'},
    {'1': 'card_last4', '3': 2, '4': 1, '5': 9, '10': 'cardLast4'},
    {'1': 'card_exp_month', '3': 3, '4': 1, '5': 13, '10': 'cardExpMonth'},
    {'1': 'card_exp_year', '3': 4, '4': 1, '5': 13, '10': 'cardExpYear'},
  ],
};

/// Descriptor for `MarketPaymentMethod`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketPaymentMethodDescriptor = $convert.base64Decode(
    'ChNNYXJrZXRQYXltZW50TWV0aG9kEh0KCmNhcmRfYnJhbmQYASABKAlSCWNhcmRCcmFuZBIdCg'
    'pjYXJkX2xhc3Q0GAIgASgJUgljYXJkTGFzdDQSJAoOY2FyZF9leHBfbW9udGgYAyABKA1SDGNh'
    'cmRFeHBNb250aBIiCg1jYXJkX2V4cF95ZWFyGAQgASgNUgtjYXJkRXhwWWVhcg==');

@$core.Deprecated('Use marketRefundDescriptor instead')
const MarketRefund$json = {
  '1': 'MarketRefund',
  '2': [
    {'1': 'amount', '3': 1, '4': 1, '5': 13, '10': 'amount'},
    {'1': 'currency', '3': 2, '4': 1, '5': 13, '10': 'currency'},
    {'1': 'market_purchase_id', '3': 3, '4': 1, '5': 9, '10': 'marketPurchaseId'},
    {'1': 'method', '3': 4, '4': 1, '5': 11, '6': '.rellm.MarketRefundMethod', '9': 0, '10': 'method', '17': true},
    {'1': 'created_at', '3': 10, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
  ],
  '8': [
    {'1': '_method'},
  ],
};

/// Descriptor for `MarketRefund`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketRefundDescriptor = $convert.base64Decode(
    'CgxNYXJrZXRSZWZ1bmQSFgoGYW1vdW50GAEgASgNUgZhbW91bnQSGgoIY3VycmVuY3kYAiABKA'
    '1SCGN1cnJlbmN5EiwKEm1hcmtldF9wdXJjaGFzZV9pZBgDIAEoCVIQbWFya2V0UHVyY2hhc2VJ'
    'ZBI2CgZtZXRob2QYBCABKAsyGS5yZWxsbS5NYXJrZXRSZWZ1bmRNZXRob2RIAFIGbWV0aG9kiA'
    'EBEjkKCmNyZWF0ZWRfYXQYCiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVh'
    'dGVkQXRCCQoHX21ldGhvZA==');

@$core.Deprecated('Use marketRefundMethodDescriptor instead')
const MarketRefundMethod$json = {
  '1': 'MarketRefundMethod',
  '2': [
    {'1': 'card_brand', '3': 1, '4': 1, '5': 9, '10': 'cardBrand'},
    {'1': 'card_last4', '3': 2, '4': 1, '5': 9, '10': 'cardLast4'},
    {'1': 'card_exp_month', '3': 3, '4': 1, '5': 13, '10': 'cardExpMonth'},
    {'1': 'card_exp_year', '3': 4, '4': 1, '5': 13, '10': 'cardExpYear'},
  ],
};

/// Descriptor for `MarketRefundMethod`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketRefundMethodDescriptor = $convert.base64Decode(
    'ChJNYXJrZXRSZWZ1bmRNZXRob2QSHQoKY2FyZF9icmFuZBgBIAEoCVIJY2FyZEJyYW5kEh0KCm'
    'NhcmRfbGFzdDQYAiABKAlSCWNhcmRMYXN0NBIkCg5jYXJkX2V4cF9tb250aBgDIAEoDVIMY2Fy'
    'ZEV4cE1vbnRoEiIKDWNhcmRfZXhwX3llYXIYBCABKA1SC2NhcmRFeHBZZWFy');

@$core.Deprecated('Use mediaStoragePurchaseDetailsDescriptor instead')
const MediaStoragePurchaseDetails$json = {
  '1': 'MediaStoragePurchaseDetails',
  '2': [
    {'1': 'allocation_bytes', '3': 1, '4': 1, '5': 4, '10': 'allocationBytes'},
  ],
};

/// Descriptor for `MediaStoragePurchaseDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaStoragePurchaseDetailsDescriptor = $convert.base64Decode(
    'ChtNZWRpYVN0b3JhZ2VQdXJjaGFzZURldGFpbHMSKQoQYWxsb2NhdGlvbl9ieXRlcxgBIAEoBF'
    'IPYWxsb2NhdGlvbkJ5dGVz');

@$core.Deprecated('Use aIGrantPurchaseDetailsDescriptor instead')
const AIGrantPurchaseDetails$json = {
  '1': 'AIGrantPurchaseDetails',
  '2': [
    {'1': 'ai_provider_id', '3': 1, '4': 1, '5': 9, '10': 'aiProviderId'},
    {'1': 'model_names', '3': 2, '4': 3, '5': 9, '10': 'modelNames'},
    {'1': 'tokens', '3': 3, '4': 1, '5': 4, '10': 'tokens'},
  ],
};

/// Descriptor for `AIGrantPurchaseDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List aIGrantPurchaseDetailsDescriptor = $convert.base64Decode(
    'ChZBSUdyYW50UHVyY2hhc2VEZXRhaWxzEiQKDmFpX3Byb3ZpZGVyX2lkGAEgASgJUgxhaVByb3'
    'ZpZGVySWQSHwoLbW9kZWxfbmFtZXMYAiADKAlSCm1vZGVsTmFtZXMSFgoGdG9rZW5zGAMgASgE'
    'UgZ0b2tlbnM=');

@$core.Deprecated('Use rellmHostingPurchaseDetailsDescriptor instead')
const RellmHostingPurchaseDetails$json = {
  '1': 'RellmHostingPurchaseDetails',
  '2': [
    {'1': 'db_size_bytes', '3': 1, '4': 1, '5': 4, '10': 'dbSizeBytes'},
    {'1': 'minio_size_bytes', '3': 2, '4': 1, '5': 4, '10': 'minioSizeBytes'},
    {'1': 'domain', '3': 3, '4': 1, '5': 9, '10': 'domain'},
    {'1': 'contact_email', '3': 4, '4': 1, '5': 9, '10': 'contactEmail'},
    {'1': 'additional_information', '3': 5, '4': 1, '5': 9, '10': 'additionalInformation'},
  ],
};

/// Descriptor for `RellmHostingPurchaseDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rellmHostingPurchaseDetailsDescriptor = $convert.base64Decode(
    'ChtSZWxsbUhvc3RpbmdQdXJjaGFzZURldGFpbHMSIgoNZGJfc2l6ZV9ieXRlcxgBIAEoBFILZG'
    'JTaXplQnl0ZXMSKAoQbWluaW9fc2l6ZV9ieXRlcxgCIAEoBFIObWluaW9TaXplQnl0ZXMSFgoG'
    'ZG9tYWluGAMgASgJUgZkb21haW4SIwoNY29udGFjdF9lbWFpbBgEIAEoCVIMY29udGFjdEVtYW'
    'lsEjUKFmFkZGl0aW9uYWxfaW5mb3JtYXRpb24YBSABKAlSFWFkZGl0aW9uYWxJbmZvcm1hdGlv'
    'bg==');

@$core.Deprecated('Use permissionsAccessPurchaseDetailsDescriptor instead')
const PermissionsAccessPurchaseDetails$json = {
  '1': 'PermissionsAccessPurchaseDetails',
  '2': [
    {'1': 'permissions', '3': 1, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'permissions'},
  ],
};

/// Descriptor for `PermissionsAccessPurchaseDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List permissionsAccessPurchaseDetailsDescriptor = $convert.base64Decode(
    'CiBQZXJtaXNzaW9uc0FjY2Vzc1B1cmNoYXNlRGV0YWlscxIzCgtwZXJtaXNzaW9ucxgBIAMoDj'
    'IRLnJlbGxtLlBlcm1pc3Npb25SC3Blcm1pc3Npb25z');

@$core.Deprecated('Use marketSubscriptionDescriptor instead')
const MarketSubscription$json = {
  '1': 'MarketSubscription',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'buyer', '3': 2, '4': 1, '5': 11, '6': '.rellm.Author', '10': 'buyer'},
    {'1': 'type', '3': 3, '4': 1, '5': 14, '6': '.rellm.PurchaseType', '10': 'type'},
    {'1': 'period', '3': 4, '4': 1, '5': 14, '6': '.rellm.PurchasePeriod', '10': 'period'},
    {'1': 'amount', '3': 5, '4': 1, '5': 13, '10': 'amount'},
    {'1': 'currency', '3': 6, '4': 1, '5': 13, '10': 'currency'},
    {'1': 'market_product', '3': 7, '4': 1, '5': 11, '6': '.rellm.MarketProduct', '10': 'marketProduct'},
    {'1': 'billing_history', '3': 8, '4': 3, '5': 11, '6': '.rellm.MarketPurchase', '10': 'billingHistory'},
    {'1': 'media_storage_subscription_details', '3': 10, '4': 1, '5': 11, '6': '.rellm.MediaStorageSubscriptionDetails', '9': 0, '10': 'mediaStorageSubscriptionDetails'},
    {'1': 'ai_grant_subscription_details', '3': 11, '4': 1, '5': 11, '6': '.rellm.AIGrantSubscriptionDetails', '9': 0, '10': 'aiGrantSubscriptionDetails'},
    {'1': 'rellm_hosting_subscription_details', '3': 12, '4': 1, '5': 11, '6': '.rellm.RellmHostingSubscriptionDetails', '9': 0, '10': 'rellmHostingSubscriptionDetails'},
    {'1': 'permissions_access_subscription_details', '3': 13, '4': 1, '5': 11, '6': '.rellm.PermissionsAccessSubscriptionDetails', '9': 0, '10': 'permissionsAccessSubscriptionDetails'},
    {'1': 'created_at', '3': 20, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'renews_at', '3': 21, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'renewsAt', '17': true},
    {'1': 'canceled_at', '3': 22, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 2, '10': 'canceledAt', '17': true},
    {'1': 'service_terminated_at', '3': 23, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 3, '10': 'serviceTerminatedAt', '17': true},
  ],
  '8': [
    {'1': 'details'},
    {'1': '_renews_at'},
    {'1': '_canceled_at'},
    {'1': '_service_terminated_at'},
  ],
};

/// Descriptor for `MarketSubscription`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketSubscriptionDescriptor = $convert.base64Decode(
    'ChJNYXJrZXRTdWJzY3JpcHRpb24SDgoCaWQYASABKAlSAmlkEiMKBWJ1eWVyGAIgASgLMg0ucm'
    'VsbG0uQXV0aG9yUgVidXllchInCgR0eXBlGAMgASgOMhMucmVsbG0uUHVyY2hhc2VUeXBlUgR0'
    'eXBlEi0KBnBlcmlvZBgEIAEoDjIVLnJlbGxtLlB1cmNoYXNlUGVyaW9kUgZwZXJpb2QSFgoGYW'
    '1vdW50GAUgASgNUgZhbW91bnQSGgoIY3VycmVuY3kYBiABKA1SCGN1cnJlbmN5EjsKDm1hcmtl'
    'dF9wcm9kdWN0GAcgASgLMhQucmVsbG0uTWFya2V0UHJvZHVjdFINbWFya2V0UHJvZHVjdBI+Cg'
    '9iaWxsaW5nX2hpc3RvcnkYCCADKAsyFS5yZWxsbS5NYXJrZXRQdXJjaGFzZVIOYmlsbGluZ0hp'
    'c3RvcnkSdQoibWVkaWFfc3RvcmFnZV9zdWJzY3JpcHRpb25fZGV0YWlscxgKIAEoCzImLnJlbG'
    'xtLk1lZGlhU3RvcmFnZVN1YnNjcmlwdGlvbkRldGFpbHNIAFIfbWVkaWFTdG9yYWdlU3Vic2Ny'
    'aXB0aW9uRGV0YWlscxJmCh1haV9ncmFudF9zdWJzY3JpcHRpb25fZGV0YWlscxgLIAEoCzIhLn'
    'JlbGxtLkFJR3JhbnRTdWJzY3JpcHRpb25EZXRhaWxzSABSGmFpR3JhbnRTdWJzY3JpcHRpb25E'
    'ZXRhaWxzEnUKInJlbGxtX2hvc3Rpbmdfc3Vic2NyaXB0aW9uX2RldGFpbHMYDCABKAsyJi5yZW'
    'xsbS5SZWxsbUhvc3RpbmdTdWJzY3JpcHRpb25EZXRhaWxzSABSH3JlbGxtSG9zdGluZ1N1YnNj'
    'cmlwdGlvbkRldGFpbHMShAEKJ3Blcm1pc3Npb25zX2FjY2Vzc19zdWJzY3JpcHRpb25fZGV0YW'
    'lscxgNIAEoCzIrLnJlbGxtLlBlcm1pc3Npb25zQWNjZXNzU3Vic2NyaXB0aW9uRGV0YWlsc0gA'
    'UiRwZXJtaXNzaW9uc0FjY2Vzc1N1YnNjcmlwdGlvbkRldGFpbHMSOQoKY3JlYXRlZF9hdBgUIA'
    'EoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWNyZWF0ZWRBdBI8CglyZW5ld3NfYXQY'
    'FSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wSAFSCHJlbmV3c0F0iAEBEkAKC2Nhbm'
    'NlbGVkX2F0GBYgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcEgCUgpjYW5jZWxlZEF0'
    'iAEBElMKFXNlcnZpY2VfdGVybWluYXRlZF9hdBgXIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW'
    '1lc3RhbXBIA1ITc2VydmljZVRlcm1pbmF0ZWRBdIgBAUIJCgdkZXRhaWxzQgwKCl9yZW5ld3Nf'
    'YXRCDgoMX2NhbmNlbGVkX2F0QhgKFl9zZXJ2aWNlX3Rlcm1pbmF0ZWRfYXQ=');

@$core.Deprecated('Use mediaStorageSubscriptionDetailsDescriptor instead')
const MediaStorageSubscriptionDetails$json = {
  '1': 'MediaStorageSubscriptionDetails',
  '2': [
    {'1': 'allocation_bytes', '3': 1, '4': 1, '5': 4, '10': 'allocationBytes'},
  ],
};

/// Descriptor for `MediaStorageSubscriptionDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaStorageSubscriptionDetailsDescriptor = $convert.base64Decode(
    'Ch9NZWRpYVN0b3JhZ2VTdWJzY3JpcHRpb25EZXRhaWxzEikKEGFsbG9jYXRpb25fYnl0ZXMYAS'
    'ABKARSD2FsbG9jYXRpb25CeXRlcw==');

@$core.Deprecated('Use aIGrantSubscriptionDetailsDescriptor instead')
const AIGrantSubscriptionDetails$json = {
  '1': 'AIGrantSubscriptionDetails',
  '2': [
    {'1': 'ai_provider_id', '3': 1, '4': 1, '5': 9, '10': 'aiProviderId'},
    {'1': 'model_names', '3': 2, '4': 3, '5': 9, '10': 'modelNames'},
    {'1': 'tokens', '3': 3, '4': 1, '5': 4, '10': 'tokens'},
  ],
};

/// Descriptor for `AIGrantSubscriptionDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List aIGrantSubscriptionDetailsDescriptor = $convert.base64Decode(
    'ChpBSUdyYW50U3Vic2NyaXB0aW9uRGV0YWlscxIkCg5haV9wcm92aWRlcl9pZBgBIAEoCVIMYW'
    'lQcm92aWRlcklkEh8KC21vZGVsX25hbWVzGAIgAygJUgptb2RlbE5hbWVzEhYKBnRva2VucxgD'
    'IAEoBFIGdG9rZW5z');

@$core.Deprecated('Use rellmHostingSubscriptionDetailsDescriptor instead')
const RellmHostingSubscriptionDetails$json = {
  '1': 'RellmHostingSubscriptionDetails',
  '2': [
    {'1': 'db_size_bytes', '3': 1, '4': 1, '5': 4, '10': 'dbSizeBytes'},
    {'1': 'minio_size_bytes', '3': 2, '4': 1, '5': 4, '10': 'minioSizeBytes'},
    {'1': 'domain', '3': 3, '4': 1, '5': 9, '10': 'domain'},
    {'1': 'contact_email', '3': 4, '4': 1, '5': 9, '10': 'contactEmail'},
    {'1': 'additional_information', '3': 5, '4': 1, '5': 9, '10': 'additionalInformation'},
    {'1': 'fulfilled', '3': 6, '4': 1, '5': 8, '10': 'fulfilled'},
    {'1': 'fulfillment_notes', '3': 7, '4': 3, '5': 11, '6': '.rellm.FulfillmentNote', '10': 'fulfillmentNotes'},
  ],
};

/// Descriptor for `RellmHostingSubscriptionDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rellmHostingSubscriptionDetailsDescriptor = $convert.base64Decode(
    'Ch9SZWxsbUhvc3RpbmdTdWJzY3JpcHRpb25EZXRhaWxzEiIKDWRiX3NpemVfYnl0ZXMYASABKA'
    'RSC2RiU2l6ZUJ5dGVzEigKEG1pbmlvX3NpemVfYnl0ZXMYAiABKARSDm1pbmlvU2l6ZUJ5dGVz'
    'EhYKBmRvbWFpbhgDIAEoCVIGZG9tYWluEiMKDWNvbnRhY3RfZW1haWwYBCABKAlSDGNvbnRhY3'
    'RFbWFpbBI1ChZhZGRpdGlvbmFsX2luZm9ybWF0aW9uGAUgASgJUhVhZGRpdGlvbmFsSW5mb3Jt'
    'YXRpb24SHAoJZnVsZmlsbGVkGAYgASgIUglmdWxmaWxsZWQSQwoRZnVsZmlsbG1lbnRfbm90ZX'
    'MYByADKAsyFi5yZWxsbS5GdWxmaWxsbWVudE5vdGVSEGZ1bGZpbGxtZW50Tm90ZXM=');

@$core.Deprecated('Use fulfillmentNoteDescriptor instead')
const FulfillmentNote$json = {
  '1': 'FulfillmentNote',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'note', '3': 2, '4': 1, '5': 9, '10': 'note'},
    {'1': 'created_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
  ],
};

/// Descriptor for `FulfillmentNote`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fulfillmentNoteDescriptor = $convert.base64Decode(
    'Cg9GdWxmaWxsbWVudE5vdGUSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEhIKBG5vdGUYAiABKA'
    'lSBG5vdGUSOQoKY3JlYXRlZF9hdBgDIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBS'
    'CWNyZWF0ZWRBdA==');

@$core.Deprecated('Use permissionsAccessSubscriptionDetailsDescriptor instead')
const PermissionsAccessSubscriptionDetails$json = {
  '1': 'PermissionsAccessSubscriptionDetails',
  '2': [
    {'1': 'permissions', '3': 1, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'permissions'},
  ],
};

/// Descriptor for `PermissionsAccessSubscriptionDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List permissionsAccessSubscriptionDetailsDescriptor = $convert.base64Decode(
    'CiRQZXJtaXNzaW9uc0FjY2Vzc1N1YnNjcmlwdGlvbkRldGFpbHMSMwoLcGVybWlzc2lvbnMYAS'
    'ADKA4yES5yZWxsbS5QZXJtaXNzaW9uUgtwZXJtaXNzaW9ucw==');

