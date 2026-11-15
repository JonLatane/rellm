//
//  Generated code. Do not modify.
//  source: contact_integrations.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use statusLevelDescriptor instead')
const StatusLevel$json = {
  '1': 'StatusLevel',
  '2': [
    {'1': 'STATUS_LEVEL_UNKNOWN', '2': 0},
    {'1': 'STATUS_LEVEL_OK', '2': 1},
    {'1': 'STATUS_LEVEL_INFO', '2': 2},
    {'1': 'STATUS_LEVEL_WARNING', '2': 3},
    {'1': 'STATUS_LEVEL_ERROR', '2': 4},
    {'1': 'STATUS_LEVEL_DISABLED', '2': 5},
  ],
};

/// Descriptor for `StatusLevel`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List statusLevelDescriptor = $convert.base64Decode(
    'CgtTdGF0dXNMZXZlbBIYChRTVEFUVVNfTEVWRUxfVU5LTk9XThAAEhMKD1NUQVRVU19MRVZFTF'
    '9PSxABEhUKEVNUQVRVU19MRVZFTF9JTkZPEAISGAoUU1RBVFVTX0xFVkVMX1dBUk5JTkcQAxIW'
    'ChJTVEFUVVNfTEVWRUxfRVJST1IQBBIZChVTVEFUVVNfTEVWRUxfRElTQUJMRUQQBQ==');

@$core.Deprecated('Use contactIntegrationsStatusDescriptor instead')
const ContactIntegrationsStatus$json = {
  '1': 'ContactIntegrationsStatus',
  '2': [
    {'1': 'checked_at', '3': 1, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'checkedAt'},
    {'1': 'sms_providers', '3': 2, '4': 3, '5': 11, '6': '.rellm.ProviderStatus', '10': 'smsProviders'},
    {'1': 'email_providers', '3': 3, '4': 3, '5': 11, '6': '.rellm.ProviderStatus', '10': 'emailProviders'},
    {'1': 'email_domains', '3': 4, '4': 3, '5': 11, '6': '.rellm.EmailDomainStatus', '10': 'emailDomains'},
  ],
};

/// Descriptor for `ContactIntegrationsStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactIntegrationsStatusDescriptor = $convert.base64Decode(
    'ChlDb250YWN0SW50ZWdyYXRpb25zU3RhdHVzEjkKCmNoZWNrZWRfYXQYASABKAsyGi5nb29nbG'
    'UucHJvdG9idWYuVGltZXN0YW1wUgljaGVja2VkQXQSOgoNc21zX3Byb3ZpZGVycxgCIAMoCzIV'
    'LnJlbGxtLlByb3ZpZGVyU3RhdHVzUgxzbXNQcm92aWRlcnMSPgoPZW1haWxfcHJvdmlkZXJzGA'
    'MgAygLMhUucmVsbG0uUHJvdmlkZXJTdGF0dXNSDmVtYWlsUHJvdmlkZXJzEj0KDWVtYWlsX2Rv'
    'bWFpbnMYBCADKAsyGC5yZWxsbS5FbWFpbERvbWFpblN0YXR1c1IMZW1haWxEb21haW5z');

@$core.Deprecated('Use providerStatusDescriptor instead')
const ProviderStatus$json = {
  '1': 'ProviderStatus',
  '2': [
    {'1': 'provider', '3': 1, '4': 1, '5': 9, '10': 'provider'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'enabled', '3': 3, '4': 1, '5': 8, '10': 'enabled'},
    {'1': 'configured', '3': 4, '4': 1, '5': 8, '10': 'configured'},
    {'1': 'level', '3': 5, '4': 1, '5': 14, '6': '.rellm.StatusLevel', '10': 'level'},
    {'1': 'summary', '3': 6, '4': 1, '5': 9, '10': 'summary'},
    {'1': 'checks', '3': 7, '4': 3, '5': 11, '6': '.rellm.StatusCheck', '10': 'checks'},
    {'1': 'metrics', '3': 8, '4': 3, '5': 11, '6': '.rellm.StatusMetric', '10': 'metrics'},
    {'1': 'dashboard_url', '3': 9, '4': 1, '5': 9, '9': 0, '10': 'dashboardUrl', '17': true},
  ],
  '8': [
    {'1': '_dashboard_url'},
  ],
};

/// Descriptor for `ProviderStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List providerStatusDescriptor = $convert.base64Decode(
    'Cg5Qcm92aWRlclN0YXR1cxIaCghwcm92aWRlchgBIAEoCVIIcHJvdmlkZXISIQoMZGlzcGxheV'
    '9uYW1lGAIgASgJUgtkaXNwbGF5TmFtZRIYCgdlbmFibGVkGAMgASgIUgdlbmFibGVkEh4KCmNv'
    'bmZpZ3VyZWQYBCABKAhSCmNvbmZpZ3VyZWQSKAoFbGV2ZWwYBSABKA4yEi5yZWxsbS5TdGF0dX'
    'NMZXZlbFIFbGV2ZWwSGAoHc3VtbWFyeRgGIAEoCVIHc3VtbWFyeRIqCgZjaGVja3MYByADKAsy'
    'Ei5yZWxsbS5TdGF0dXNDaGVja1IGY2hlY2tzEi0KB21ldHJpY3MYCCADKAsyEy5yZWxsbS5TdG'
    'F0dXNNZXRyaWNSB21ldHJpY3MSKAoNZGFzaGJvYXJkX3VybBgJIAEoCUgAUgxkYXNoYm9hcmRV'
    'cmyIAQFCEAoOX2Rhc2hib2FyZF91cmw=');

@$core.Deprecated('Use statusCheckDescriptor instead')
const StatusCheck$json = {
  '1': 'StatusCheck',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'level', '3': 2, '4': 1, '5': 14, '6': '.rellm.StatusLevel', '10': 'level'},
    {'1': 'detail', '3': 3, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'fix_hint', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'fixHint', '17': true},
  ],
  '8': [
    {'1': '_fix_hint'},
  ],
};

/// Descriptor for `StatusCheck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusCheckDescriptor = $convert.base64Decode(
    'CgtTdGF0dXNDaGVjaxISCgRuYW1lGAEgASgJUgRuYW1lEigKBWxldmVsGAIgASgOMhIucmVsbG'
    '0uU3RhdHVzTGV2ZWxSBWxldmVsEhYKBmRldGFpbBgDIAEoCVIGZGV0YWlsEh4KCGZpeF9oaW50'
    'GAQgASgJSABSB2ZpeEhpbnSIAQFCCwoJX2ZpeF9oaW50');

@$core.Deprecated('Use statusMetricDescriptor instead')
const StatusMetric$json = {
  '1': 'StatusMetric',
  '2': [
    {'1': 'label', '3': 1, '4': 1, '5': 9, '10': 'label'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
    {'1': 'detail', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'detail', '17': true},
  ],
  '8': [
    {'1': '_detail'},
  ],
};

/// Descriptor for `StatusMetric`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusMetricDescriptor = $convert.base64Decode(
    'CgxTdGF0dXNNZXRyaWMSFAoFbGFiZWwYASABKAlSBWxhYmVsEhQKBXZhbHVlGAIgASgJUgV2YW'
    'x1ZRIbCgZkZXRhaWwYAyABKAlIAFIGZGV0YWlsiAEBQgkKB19kZXRhaWw=');

@$core.Deprecated('Use emailDomainStatusDescriptor instead')
const EmailDomainStatus$json = {
  '1': 'EmailDomainStatus',
  '2': [
    {'1': 'domain', '3': 1, '4': 1, '5': 9, '10': 'domain'},
    {'1': 'used_by', '3': 2, '4': 3, '5': 9, '10': 'usedBy'},
    {'1': 'level', '3': 3, '4': 1, '5': 14, '6': '.rellm.StatusLevel', '10': 'level'},
    {'1': 'summary', '3': 4, '4': 1, '5': 9, '10': 'summary'},
    {'1': 'dmarc', '3': 5, '4': 1, '5': 11, '6': '.rellm.DmarcStatus', '10': 'dmarc'},
    {'1': 'checks', '3': 6, '4': 3, '5': 11, '6': '.rellm.StatusCheck', '10': 'checks'},
  ],
};

/// Descriptor for `EmailDomainStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emailDomainStatusDescriptor = $convert.base64Decode(
    'ChFFbWFpbERvbWFpblN0YXR1cxIWCgZkb21haW4YASABKAlSBmRvbWFpbhIXCgd1c2VkX2J5GA'
    'IgAygJUgZ1c2VkQnkSKAoFbGV2ZWwYAyABKA4yEi5yZWxsbS5TdGF0dXNMZXZlbFIFbGV2ZWwS'
    'GAoHc3VtbWFyeRgEIAEoCVIHc3VtbWFyeRIoCgVkbWFyYxgFIAEoCzISLnJlbGxtLkRtYXJjU3'
    'RhdHVzUgVkbWFyYxIqCgZjaGVja3MYBiADKAsyEi5yZWxsbS5TdGF0dXNDaGVja1IGY2hlY2tz');

@$core.Deprecated('Use dmarcStatusDescriptor instead')
const DmarcStatus$json = {
  '1': 'DmarcStatus',
  '2': [
    {'1': 'record_found', '3': 1, '4': 1, '5': 8, '10': 'recordFound'},
    {'1': 'raw_record', '3': 2, '4': 1, '5': 9, '10': 'rawRecord'},
    {'1': 'policy', '3': 3, '4': 1, '5': 9, '10': 'policy'},
    {'1': 'subdomain_policy', '3': 4, '4': 1, '5': 9, '10': 'subdomainPolicy'},
    {'1': 'percentage', '3': 5, '4': 1, '5': 5, '10': 'percentage'},
    {'1': 'aggregate_report_uris', '3': 6, '4': 3, '5': 9, '10': 'aggregateReportUris'},
    {'1': 'forensic_report_uris', '3': 7, '4': 3, '5': 9, '10': 'forensicReportUris'},
    {'1': 'dkim_alignment', '3': 8, '4': 1, '5': 9, '10': 'dkimAlignment'},
    {'1': 'spf_alignment', '3': 9, '4': 1, '5': 9, '10': 'spfAlignment'},
    {'1': 'level', '3': 10, '4': 1, '5': 14, '6': '.rellm.StatusLevel', '10': 'level'},
    {'1': 'summary', '3': 11, '4': 1, '5': 9, '10': 'summary'},
  ],
};

/// Descriptor for `DmarcStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dmarcStatusDescriptor = $convert.base64Decode(
    'CgtEbWFyY1N0YXR1cxIhCgxyZWNvcmRfZm91bmQYASABKAhSC3JlY29yZEZvdW5kEh0KCnJhd1'
    '9yZWNvcmQYAiABKAlSCXJhd1JlY29yZBIWCgZwb2xpY3kYAyABKAlSBnBvbGljeRIpChBzdWJk'
    'b21haW5fcG9saWN5GAQgASgJUg9zdWJkb21haW5Qb2xpY3kSHgoKcGVyY2VudGFnZRgFIAEoBV'
    'IKcGVyY2VudGFnZRIyChVhZ2dyZWdhdGVfcmVwb3J0X3VyaXMYBiADKAlSE2FnZ3JlZ2F0ZVJl'
    'cG9ydFVyaXMSMAoUZm9yZW5zaWNfcmVwb3J0X3VyaXMYByADKAlSEmZvcmVuc2ljUmVwb3J0VX'
    'JpcxIlCg5ka2ltX2FsaWdubWVudBgIIAEoCVINZGtpbUFsaWdubWVudBIjCg1zcGZfYWxpZ25t'
    'ZW50GAkgASgJUgxzcGZBbGlnbm1lbnQSKAoFbGV2ZWwYCiABKA4yEi5yZWxsbS5TdGF0dXNMZX'
    'ZlbFIFbGV2ZWwSGAoHc3VtbWFyeRgLIAEoCVIHc3VtbWFyeQ==');

