//
//  Generated code. Do not modify.
//  source: server_configuration.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use clusterResourceDescriptor instead')
const ClusterResource$json = {
  '1': 'ClusterResource',
  '2': [
    {'1': 'CLUSTER_RESOURCE_BROWSER', '2': 0},
    {'1': 'CLUSTER_RESOURCE_FFMPEG', '2': 1},
    {'1': 'CLUSTER_RESOURCE_IMAGEMAGICK', '2': 2},
  ],
};

/// Descriptor for `ClusterResource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List clusterResourceDescriptor = $convert.base64Decode(
    'Cg9DbHVzdGVyUmVzb3VyY2USHAoYQ0xVU1RFUl9SRVNPVVJDRV9CUk9XU0VSEAASGwoXQ0xVU1'
    'RFUl9SRVNPVVJDRV9GRk1QRUcQARIgChxDTFVTVEVSX1JFU09VUkNFX0lNQUdFTUFHSUNLEAI=');

@$core.Deprecated('Use authenticationFeatureDescriptor instead')
const AuthenticationFeature$json = {
  '1': 'AuthenticationFeature',
  '2': [
    {'1': 'AUTHENTICATION_FEATURE_UNKNOWN', '2': 0},
    {'1': 'CREATE_ACCOUNT', '2': 1},
    {'1': 'LOGIN', '2': 2},
  ],
};

/// Descriptor for `AuthenticationFeature`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List authenticationFeatureDescriptor = $convert.base64Decode(
    'ChVBdXRoZW50aWNhdGlvbkZlYXR1cmUSIgoeQVVUSEVOVElDQVRJT05fRkVBVFVSRV9VTktOT1'
    'dOEAASEgoOQ1JFQVRFX0FDQ09VTlQQARIJCgVMT0dJThAC');

@$core.Deprecated('Use calendarDisplayModeDescriptor instead')
const CalendarDisplayMode$json = {
  '1': 'CalendarDisplayMode',
  '2': [
    {'1': 'CALENDAR_DISPLAY_WEEK', '2': 0},
    {'1': 'CALENDAR_DISPLAY_MONTH', '2': 1},
    {'1': 'CALENDAR_DISPLAY_DAY', '2': 3},
  ],
};

/// Descriptor for `CalendarDisplayMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List calendarDisplayModeDescriptor = $convert.base64Decode(
    'ChNDYWxlbmRhckRpc3BsYXlNb2RlEhkKFUNBTEVOREFSX0RJU1BMQVlfV0VFSxAAEhoKFkNBTE'
    'VOREFSX0RJU1BMQVlfTU9OVEgQARIYChRDQUxFTkRBUl9ESVNQTEFZX0RBWRAD');

@$core.Deprecated('Use privateUserStrategyDescriptor instead')
const PrivateUserStrategy$json = {
  '1': 'PrivateUserStrategy',
  '2': [
    {'1': 'ACCOUNT_IS_FROZEN', '2': 0},
    {'1': 'LIMITED_CREEPINESS', '2': 1},
    {'1': 'LET_ME_CREEP_ON_PPL', '2': 2},
  ],
};

/// Descriptor for `PrivateUserStrategy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List privateUserStrategyDescriptor = $convert.base64Decode(
    'ChNQcml2YXRlVXNlclN0cmF0ZWd5EhUKEUFDQ09VTlRfSVNfRlJPWkVOEAASFgoSTElNSVRFRF'
    '9DUkVFUElORVNTEAESFwoTTEVUX01FX0NSRUVQX09OX1BQTBAC');

@$core.Deprecated('Use webUserInterfaceDescriptor instead')
const WebUserInterface$json = {
  '1': 'WebUserInterface',
  '2': [
    {'1': 'FLUTTER_WEB', '2': 0},
    {
      '1': 'HANDLEBARS_TEMPLATES',
      '2': 1,
      '3': {'1': true},
    },
    {'1': 'REACT_TAMAGUI', '2': 2},
    {'1': 'ELM_SPA', '2': 3},
  ],
};

/// Descriptor for `WebUserInterface`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List webUserInterfaceDescriptor = $convert.base64Decode(
    'ChBXZWJVc2VySW50ZXJmYWNlEg8KC0ZMVVRURVJfV0VCEAASHAoUSEFORExFQkFSU19URU1QTE'
    'FURVMQARoCCAESEQoNUkVBQ1RfVEFNQUdVSRACEgsKB0VMTV9TUEEQAw==');

@$core.Deprecated('Use navigationTabStyleDescriptor instead')
const NavigationTabStyle$json = {
  '1': 'NavigationTabStyle',
  '2': [
    {'1': 'NAVIGATION_TAB_ICON_ONLY', '2': 0},
    {'1': 'NAVIGATION_TAB_TEXT_ONLY', '2': 1},
    {'1': 'NAVIGATION_TAB_ICON_AND_TEXT_BELOW', '2': 2},
    {'1': 'NAVIGATION_TAB_ICON_AND_TEXT_RIGHT', '2': 3},
  ],
};

/// Descriptor for `NavigationTabStyle`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List navigationTabStyleDescriptor = $convert.base64Decode(
    'ChJOYXZpZ2F0aW9uVGFiU3R5bGUSHAoYTkFWSUdBVElPTl9UQUJfSUNPTl9PTkxZEAASHAoYTk'
    'FWSUdBVElPTl9UQUJfVEVYVF9PTkxZEAESJgoiTkFWSUdBVElPTl9UQUJfSUNPTl9BTkRfVEVY'
    'VF9CRUxPVxACEiYKIk5BVklHQVRJT05fVEFCX0lDT05fQU5EX1RFWFRfUklHSFQQAw==');

@$core.Deprecated('Use navigationTabDescriptor instead')
const NavigationTab$json = {
  '1': 'NavigationTab',
  '2': [
    {'1': 'HOME_TAB', '2': 0},
    {'1': 'EVENTS_TAB', '2': 10},
    {'1': 'POSTS_TAB', '2': 11},
    {'1': 'PEOPLE_TAB', '2': 12},
    {'1': 'ABOUT_TAB', '2': 15},
    {'1': 'MARKET_TAB', '2': 16},
  ],
};

/// Descriptor for `NavigationTab`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List navigationTabDescriptor = $convert.base64Decode(
    'Cg1OYXZpZ2F0aW9uVGFiEgwKCEhPTUVfVEFCEAASDgoKRVZFTlRTX1RBQhAKEg0KCVBPU1RTX1'
    'RBQhALEg4KClBFT1BMRV9UQUIQDBINCglBQk9VVF9UQUIQDxIOCgpNQVJLRVRfVEFCEBA=');

@$core.Deprecated('Use verificationAPIDescriptor instead')
const VerificationAPI$json = {
  '1': 'VerificationAPI',
  '2': [
    {'1': 'VERIFICATION_API_TWILIO', '2': 0},
    {'1': 'VERIFICATION_API_BIRD', '2': 1},
  ],
};

/// Descriptor for `VerificationAPI`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List verificationAPIDescriptor = $convert.base64Decode(
    'Cg9WZXJpZmljYXRpb25BUEkSGwoXVkVSSUZJQ0FUSU9OX0FQSV9UV0lMSU8QABIZChVWRVJJRk'
    'lDQVRJT05fQVBJX0JJUkQQAQ==');

@$core.Deprecated('Use serverConfigurationDescriptor instead')
const ServerConfiguration$json = {
  '1': 'ServerConfiguration',
  '2': [
    {'1': 'server_info', '3': 1, '4': 1, '5': 11, '6': '.rellm.ServerInfo', '9': 0, '10': 'serverInfo', '17': true},
    {'1': 'federation_info', '3': 2, '4': 1, '5': 11, '6': '.rellm.FederationInfo', '9': 1, '10': 'federationInfo', '17': true},
    {'1': 'anonymous_user_permissions', '3': 10, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'anonymousUserPermissions'},
    {'1': 'default_user_permissions', '3': 11, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'defaultUserPermissions'},
    {'1': 'basic_user_permissions', '3': 12, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'basicUserPermissions'},
    {'1': 'custom_tabs', '3': 19, '4': 1, '5': 11, '6': '.rellm.CustomNavigationTabSet', '9': 2, '10': 'customTabs', '17': true},
    {'1': 'people_settings', '3': 20, '4': 1, '5': 11, '6': '.rellm.FeatureSettings', '10': 'peopleSettings'},
    {'1': 'group_settings', '3': 21, '4': 1, '5': 11, '6': '.rellm.FeatureSettings', '10': 'groupSettings'},
    {'1': 'post_settings', '3': 22, '4': 1, '5': 11, '6': '.rellm.PostSettings', '10': 'postSettings'},
    {'1': 'event_settings', '3': 23, '4': 1, '5': 11, '6': '.rellm.EventSettings', '10': 'eventSettings'},
    {'1': 'media_settings', '3': 24, '4': 1, '5': 11, '6': '.rellm.MediaSettings', '10': 'mediaSettings'},
    {'1': 'market_settings', '3': 25, '4': 1, '5': 11, '6': '.rellm.MarketSettings', '10': 'marketSettings'},
    {'1': 'external_cdn_config', '3': 90, '4': 1, '5': 11, '6': '.rellm.ExternalCDNConfig', '9': 3, '10': 'externalCdnConfig', '17': true},
    {'1': 'cluster_resources', '3': 91, '4': 1, '5': 11, '6': '.rellm.ClusterResources', '9': 4, '10': 'clusterResources', '17': true},
    {'1': 'private_user_strategy', '3': 100, '4': 1, '5': 14, '6': '.rellm.PrivateUserStrategy', '10': 'privateUserStrategy'},
    {'1': 'authentication_features', '3': 101, '4': 3, '5': 14, '6': '.rellm.AuthenticationFeature', '10': 'authenticationFeatures'},
    {'1': 'web_push_config', '3': 110, '4': 1, '5': 11, '6': '.rellm.WebPushConfig', '9': 5, '10': 'webPushConfig', '17': true},
    {'1': 'preferred_verification_apis', '3': 120, '4': 3, '5': 14, '6': '.rellm.VerificationAPI', '10': 'preferredVerificationApis'},
    {'1': 'available_verification_apis', '3': 121, '4': 3, '5': 14, '6': '.rellm.VerificationAPI', '10': 'availableVerificationApis'},
    {'1': 'twilio_config', '3': 122, '4': 1, '5': 11, '6': '.rellm.TwilioConfig', '9': 6, '10': 'twilioConfig', '17': true},
    {'1': 'bird_config', '3': 123, '4': 1, '5': 11, '6': '.rellm.BirdConfig', '9': 7, '10': 'birdConfig', '17': true},
    {'1': 'stripe_config', '3': 124, '4': 1, '5': 11, '6': '.rellm.StripeConfig', '9': 8, '10': 'stripeConfig', '17': true},
  ],
  '8': [
    {'1': '_server_info'},
    {'1': '_federation_info'},
    {'1': '_custom_tabs'},
    {'1': '_external_cdn_config'},
    {'1': '_cluster_resources'},
    {'1': '_web_push_config'},
    {'1': '_twilio_config'},
    {'1': '_bird_config'},
    {'1': '_stripe_config'},
  ],
};

/// Descriptor for `ServerConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverConfigurationDescriptor = $convert.base64Decode(
    'ChNTZXJ2ZXJDb25maWd1cmF0aW9uEjcKC3NlcnZlcl9pbmZvGAEgASgLMhEucmVsbG0uU2Vydm'
    'VySW5mb0gAUgpzZXJ2ZXJJbmZviAEBEkMKD2ZlZGVyYXRpb25faW5mbxgCIAEoCzIVLnJlbGxt'
    'LkZlZGVyYXRpb25JbmZvSAFSDmZlZGVyYXRpb25JbmZviAEBEk8KGmFub255bW91c191c2VyX3'
    'Blcm1pc3Npb25zGAogAygOMhEucmVsbG0uUGVybWlzc2lvblIYYW5vbnltb3VzVXNlclBlcm1p'
    'c3Npb25zEksKGGRlZmF1bHRfdXNlcl9wZXJtaXNzaW9ucxgLIAMoDjIRLnJlbGxtLlBlcm1pc3'
    'Npb25SFmRlZmF1bHRVc2VyUGVybWlzc2lvbnMSRwoWYmFzaWNfdXNlcl9wZXJtaXNzaW9ucxgM'
    'IAMoDjIRLnJlbGxtLlBlcm1pc3Npb25SFGJhc2ljVXNlclBlcm1pc3Npb25zEkMKC2N1c3RvbV'
    '90YWJzGBMgASgLMh0ucmVsbG0uQ3VzdG9tTmF2aWdhdGlvblRhYlNldEgCUgpjdXN0b21UYWJz'
    'iAEBEj8KD3Blb3BsZV9zZXR0aW5ncxgUIAEoCzIWLnJlbGxtLkZlYXR1cmVTZXR0aW5nc1IOcG'
    'VvcGxlU2V0dGluZ3MSPQoOZ3JvdXBfc2V0dGluZ3MYFSABKAsyFi5yZWxsbS5GZWF0dXJlU2V0'
    'dGluZ3NSDWdyb3VwU2V0dGluZ3MSOAoNcG9zdF9zZXR0aW5ncxgWIAEoCzITLnJlbGxtLlBvc3'
    'RTZXR0aW5nc1IMcG9zdFNldHRpbmdzEjsKDmV2ZW50X3NldHRpbmdzGBcgASgLMhQucmVsbG0u'
    'RXZlbnRTZXR0aW5nc1INZXZlbnRTZXR0aW5ncxI7Cg5tZWRpYV9zZXR0aW5ncxgYIAEoCzIULn'
    'JlbGxtLk1lZGlhU2V0dGluZ3NSDW1lZGlhU2V0dGluZ3MSPgoPbWFya2V0X3NldHRpbmdzGBkg'
    'ASgLMhUucmVsbG0uTWFya2V0U2V0dGluZ3NSDm1hcmtldFNldHRpbmdzEk0KE2V4dGVybmFsX2'
    'Nkbl9jb25maWcYWiABKAsyGC5yZWxsbS5FeHRlcm5hbENETkNvbmZpZ0gDUhFleHRlcm5hbENk'
    'bkNvbmZpZ4gBARJJChFjbHVzdGVyX3Jlc291cmNlcxhbIAEoCzIXLnJlbGxtLkNsdXN0ZXJSZX'
    'NvdXJjZXNIBFIQY2x1c3RlclJlc291cmNlc4gBARJOChVwcml2YXRlX3VzZXJfc3RyYXRlZ3kY'
    'ZCABKA4yGi5yZWxsbS5Qcml2YXRlVXNlclN0cmF0ZWd5UhNwcml2YXRlVXNlclN0cmF0ZWd5El'
    'UKF2F1dGhlbnRpY2F0aW9uX2ZlYXR1cmVzGGUgAygOMhwucmVsbG0uQXV0aGVudGljYXRpb25G'
    'ZWF0dXJlUhZhdXRoZW50aWNhdGlvbkZlYXR1cmVzEkEKD3dlYl9wdXNoX2NvbmZpZxhuIAEoCz'
    'IULnJlbGxtLldlYlB1c2hDb25maWdIBVINd2ViUHVzaENvbmZpZ4gBARJWChtwcmVmZXJyZWRf'
    'dmVyaWZpY2F0aW9uX2FwaXMYeCADKA4yFi5yZWxsbS5WZXJpZmljYXRpb25BUElSGXByZWZlcn'
    'JlZFZlcmlmaWNhdGlvbkFwaXMSVgobYXZhaWxhYmxlX3ZlcmlmaWNhdGlvbl9hcGlzGHkgAygO'
    'MhYucmVsbG0uVmVyaWZpY2F0aW9uQVBJUhlhdmFpbGFibGVWZXJpZmljYXRpb25BcGlzEj0KDX'
    'R3aWxpb19jb25maWcYeiABKAsyEy5yZWxsbS5Ud2lsaW9Db25maWdIBlIMdHdpbGlvQ29uZmln'
    'iAEBEjcKC2JpcmRfY29uZmlnGHsgASgLMhEucmVsbG0uQmlyZENvbmZpZ0gHUgpiaXJkQ29uZm'
    'lniAEBEj0KDXN0cmlwZV9jb25maWcYfCABKAsyEy5yZWxsbS5TdHJpcGVDb25maWdICFIMc3Ry'
    'aXBlQ29uZmlniAEBQg4KDF9zZXJ2ZXJfaW5mb0ISChBfZmVkZXJhdGlvbl9pbmZvQg4KDF9jdX'
    'N0b21fdGFic0IWChRfZXh0ZXJuYWxfY2RuX2NvbmZpZ0IUChJfY2x1c3Rlcl9yZXNvdXJjZXNC'
    'EgoQX3dlYl9wdXNoX2NvbmZpZ0IQCg5fdHdpbGlvX2NvbmZpZ0IOCgxfYmlyZF9jb25maWdCEA'
    'oOX3N0cmlwZV9jb25maWc=');

@$core.Deprecated('Use clusterResourcesDescriptor instead')
const ClusterResources$json = {
  '1': 'ClusterResources',
  '2': [
    {'1': 'namespace_id', '3': 1, '4': 1, '5': 9, '10': 'namespaceId'},
    {'1': 'conductor_host', '3': 2, '4': 1, '5': 9, '10': 'conductorHost'},
    {'1': 'cluster_shared_secret', '3': 3, '4': 1, '5': 9, '10': 'clusterSharedSecret'},
    {'1': 'conductor_state', '3': 4, '4': 1, '5': 11, '6': '.rellm.ClusterConductorState', '9': 0, '10': 'conductorState', '17': true},
  ],
  '8': [
    {'1': '_conductor_state'},
  ],
};

/// Descriptor for `ClusterResources`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clusterResourcesDescriptor = $convert.base64Decode(
    'ChBDbHVzdGVyUmVzb3VyY2VzEiEKDG5hbWVzcGFjZV9pZBgBIAEoCVILbmFtZXNwYWNlSWQSJQ'
    'oOY29uZHVjdG9yX2hvc3QYAiABKAlSDWNvbmR1Y3Rvckhvc3QSMgoVY2x1c3Rlcl9zaGFyZWRf'
    'c2VjcmV0GAMgASgJUhNjbHVzdGVyU2hhcmVkU2VjcmV0EkoKD2NvbmR1Y3Rvcl9zdGF0ZRgEIA'
    'EoCzIcLnJlbGxtLkNsdXN0ZXJDb25kdWN0b3JTdGF0ZUgAUg5jb25kdWN0b3JTdGF0ZYgBAUIS'
    'ChBfY29uZHVjdG9yX3N0YXRl');

@$core.Deprecated('Use clusterConductorStateDescriptor instead')
const ClusterConductorState$json = {
  '1': 'ClusterConductorState',
  '2': [
    {'1': 'locks', '3': 1, '4': 3, '5': 11, '6': '.rellm.ClusterResourceLock', '10': 'locks'},
    {'1': 'limits', '3': 2, '4': 3, '5': 11, '6': '.rellm.ClusterResourceLimit', '10': 'limits'},
  ],
};

/// Descriptor for `ClusterConductorState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clusterConductorStateDescriptor = $convert.base64Decode(
    'ChVDbHVzdGVyQ29uZHVjdG9yU3RhdGUSMAoFbG9ja3MYASADKAsyGi5yZWxsbS5DbHVzdGVyUm'
    'Vzb3VyY2VMb2NrUgVsb2NrcxIzCgZsaW1pdHMYAiADKAsyGy5yZWxsbS5DbHVzdGVyUmVzb3Vy'
    'Y2VMaW1pdFIGbGltaXRz');

@$core.Deprecated('Use clusterResourceLockDescriptor instead')
const ClusterResourceLock$json = {
  '1': 'ClusterResourceLock',
  '2': [
    {'1': 'lock_holder_namespace_id', '3': 1, '4': 1, '5': 9, '10': 'lockHolderNamespaceId'},
    {'1': 'resources', '3': 2, '4': 3, '5': 14, '6': '.rellm.ClusterResource', '10': 'resources'},
    {'1': 'acquired_at', '3': 20, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'acquiredAt'},
  ],
};

/// Descriptor for `ClusterResourceLock`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clusterResourceLockDescriptor = $convert.base64Decode(
    'ChNDbHVzdGVyUmVzb3VyY2VMb2NrEjcKGGxvY2tfaG9sZGVyX25hbWVzcGFjZV9pZBgBIAEoCV'
    'IVbG9ja0hvbGRlck5hbWVzcGFjZUlkEjQKCXJlc291cmNlcxgCIAMoDjIWLnJlbGxtLkNsdXN0'
    'ZXJSZXNvdXJjZVIJcmVzb3VyY2VzEjsKC2FjcXVpcmVkX2F0GBQgASgLMhouZ29vZ2xlLnByb3'
    'RvYnVmLlRpbWVzdGFtcFIKYWNxdWlyZWRBdA==');

@$core.Deprecated('Use clusterResourceLimitDescriptor instead')
const ClusterResourceLimit$json = {
  '1': 'ClusterResourceLimit',
  '2': [
    {'1': 'resource', '3': 1, '4': 3, '5': 14, '6': '.rellm.ClusterResource', '10': 'resource'},
    {'1': 'limit', '3': 2, '4': 3, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `ClusterResourceLimit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clusterResourceLimitDescriptor = $convert.base64Decode(
    'ChRDbHVzdGVyUmVzb3VyY2VMaW1pdBIyCghyZXNvdXJjZRgBIAMoDjIWLnJlbGxtLkNsdXN0ZX'
    'JSZXNvdXJjZVIIcmVzb3VyY2USFAoFbGltaXQYAiADKA1SBWxpbWl0');

@$core.Deprecated('Use lockClusterResourcesRequestDescriptor instead')
const LockClusterResourcesRequest$json = {
  '1': 'LockClusterResourcesRequest',
  '2': [
    {'1': 'namespace_id', '3': 1, '4': 1, '5': 9, '10': 'namespaceId'},
    {'1': 'resources', '3': 2, '4': 3, '5': 14, '6': '.rellm.ClusterResource', '10': 'resources'},
  ],
};

/// Descriptor for `LockClusterResourcesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lockClusterResourcesRequestDescriptor = $convert.base64Decode(
    'ChtMb2NrQ2x1c3RlclJlc291cmNlc1JlcXVlc3QSIQoMbmFtZXNwYWNlX2lkGAEgASgJUgtuYW'
    '1lc3BhY2VJZBI0CglyZXNvdXJjZXMYAiADKA4yFi5yZWxsbS5DbHVzdGVyUmVzb3VyY2VSCXJl'
    'c291cmNlcw==');

@$core.Deprecated('Use lockClusterResourcesResponseDescriptor instead')
const LockClusterResourcesResponse$json = {
  '1': 'LockClusterResourcesResponse',
  '2': [
    {'1': 'granted', '3': 1, '4': 1, '5': 8, '10': 'granted'},
    {'1': 'holder', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'holder', '17': true},
  ],
  '8': [
    {'1': '_holder'},
  ],
};

/// Descriptor for `LockClusterResourcesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lockClusterResourcesResponseDescriptor = $convert.base64Decode(
    'ChxMb2NrQ2x1c3RlclJlc291cmNlc1Jlc3BvbnNlEhgKB2dyYW50ZWQYASABKAhSB2dyYW50ZW'
    'QSGwoGaG9sZGVyGAIgASgJSABSBmhvbGRlcogBAUIJCgdfaG9sZGVy');

@$core.Deprecated('Use freeClusterResourcesRequestDescriptor instead')
const FreeClusterResourcesRequest$json = {
  '1': 'FreeClusterResourcesRequest',
  '2': [
    {'1': 'namespace_id', '3': 1, '4': 1, '5': 9, '10': 'namespaceId'},
    {'1': 'resources', '3': 2, '4': 3, '5': 14, '6': '.rellm.ClusterResource', '10': 'resources'},
  ],
};

/// Descriptor for `FreeClusterResourcesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List freeClusterResourcesRequestDescriptor = $convert.base64Decode(
    'ChtGcmVlQ2x1c3RlclJlc291cmNlc1JlcXVlc3QSIQoMbmFtZXNwYWNlX2lkGAEgASgJUgtuYW'
    '1lc3BhY2VJZBI0CglyZXNvdXJjZXMYAiADKA4yFi5yZWxsbS5DbHVzdGVyUmVzb3VyY2VSCXJl'
    'c291cmNlcw==');

@$core.Deprecated('Use externalCDNConfigDescriptor instead')
const ExternalCDNConfig$json = {
  '1': 'ExternalCDNConfig',
  '2': [
    {'1': 'frontend_host', '3': 1, '4': 1, '5': 9, '10': 'frontendHost'},
    {'1': 'backend_host', '3': 2, '4': 1, '5': 9, '10': 'backendHost'},
    {'1': 'secure_media', '3': 3, '4': 1, '5': 8, '10': 'secureMedia'},
    {'1': 'media_ipv4_allowlist', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'mediaIpv4Allowlist', '17': true},
    {'1': 'media_ipv6_allowlist', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'mediaIpv6Allowlist', '17': true},
    {'1': 'cdn_grpc', '3': 6, '4': 1, '5': 8, '10': 'cdnGrpc'},
  ],
  '8': [
    {'1': '_media_ipv4_allowlist'},
    {'1': '_media_ipv6_allowlist'},
  ],
};

/// Descriptor for `ExternalCDNConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List externalCDNConfigDescriptor = $convert.base64Decode(
    'ChFFeHRlcm5hbENETkNvbmZpZxIjCg1mcm9udGVuZF9ob3N0GAEgASgJUgxmcm9udGVuZEhvc3'
    'QSIQoMYmFja2VuZF9ob3N0GAIgASgJUgtiYWNrZW5kSG9zdBIhCgxzZWN1cmVfbWVkaWEYAyAB'
    'KAhSC3NlY3VyZU1lZGlhEjUKFG1lZGlhX2lwdjRfYWxsb3dsaXN0GAQgASgJSABSEm1lZGlhSX'
    'B2NEFsbG93bGlzdIgBARI1ChRtZWRpYV9pcHY2X2FsbG93bGlzdBgFIAEoCUgBUhJtZWRpYUlw'
    'djZBbGxvd2xpc3SIAQESGQoIY2RuX2dycGMYBiABKAhSB2NkbkdycGNCFwoVX21lZGlhX2lwdj'
    'RfYWxsb3dsaXN0QhcKFV9tZWRpYV9pcHY2X2FsbG93bGlzdA==');

@$core.Deprecated('Use mediaSettingsDescriptor instead')
const MediaSettings$json = {
  '1': 'MediaSettings',
  '2': [
    {'1': 'visible', '3': 1, '4': 1, '5': 8, '10': 'visible'},
    {'1': 'default_moderation', '3': 2, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'defaultModeration'},
    {'1': 'default_visibility', '3': 3, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'defaultVisibility'},
    {'1': 'default_media_allocation_bytes', '3': 4, '4': 1, '5': 4, '10': 'defaultMediaAllocationBytes'},
  ],
};

/// Descriptor for `MediaSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaSettingsDescriptor = $convert.base64Decode(
    'Cg1NZWRpYVNldHRpbmdzEhgKB3Zpc2libGUYASABKAhSB3Zpc2libGUSQAoSZGVmYXVsdF9tb2'
    'RlcmF0aW9uGAIgASgOMhEucmVsbG0uTW9kZXJhdGlvblIRZGVmYXVsdE1vZGVyYXRpb24SQAoS'
    'ZGVmYXVsdF92aXNpYmlsaXR5GAMgASgOMhEucmVsbG0uVmlzaWJpbGl0eVIRZGVmYXVsdFZpc2'
    'liaWxpdHkSQwoeZGVmYXVsdF9tZWRpYV9hbGxvY2F0aW9uX2J5dGVzGAQgASgEUhtkZWZhdWx0'
    'TWVkaWFBbGxvY2F0aW9uQnl0ZXM=');

@$core.Deprecated('Use marketSettingsDescriptor instead')
const MarketSettings$json = {
  '1': 'MarketSettings',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
    {'1': 'stripe_configured', '3': 2, '4': 1, '5': 8, '10': 'stripeConfigured'},
  ],
};

/// Descriptor for `MarketSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List marketSettingsDescriptor = $convert.base64Decode(
    'Cg5NYXJrZXRTZXR0aW5ncxIYCgdlbmFibGVkGAEgASgIUgdlbmFibGVkEisKEXN0cmlwZV9jb2'
    '5maWd1cmVkGAIgASgIUhBzdHJpcGVDb25maWd1cmVk');

@$core.Deprecated('Use featureSettingsDescriptor instead')
const FeatureSettings$json = {
  '1': 'FeatureSettings',
  '2': [
    {'1': 'visible', '3': 1, '4': 1, '5': 8, '10': 'visible'},
    {'1': 'default_moderation', '3': 2, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'defaultModeration'},
    {'1': 'default_visibility', '3': 3, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'defaultVisibility'},
    {'1': 'alias_singular', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'aliasSingular', '17': true},
    {'1': 'alias_plural', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'aliasPlural', '17': true},
  ],
  '8': [
    {'1': '_alias_singular'},
    {'1': '_alias_plural'},
  ],
};

/// Descriptor for `FeatureSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List featureSettingsDescriptor = $convert.base64Decode(
    'Cg9GZWF0dXJlU2V0dGluZ3MSGAoHdmlzaWJsZRgBIAEoCFIHdmlzaWJsZRJAChJkZWZhdWx0X2'
    '1vZGVyYXRpb24YAiABKA4yES5yZWxsbS5Nb2RlcmF0aW9uUhFkZWZhdWx0TW9kZXJhdGlvbhJA'
    'ChJkZWZhdWx0X3Zpc2liaWxpdHkYAyABKA4yES5yZWxsbS5WaXNpYmlsaXR5UhFkZWZhdWx0Vm'
    'lzaWJpbGl0eRIqCg5hbGlhc19zaW5ndWxhchgEIAEoCUgAUg1hbGlhc1Npbmd1bGFyiAEBEiYK'
    'DGFsaWFzX3BsdXJhbBgFIAEoCUgBUgthbGlhc1BsdXJhbIgBAUIRCg9fYWxpYXNfc2luZ3VsYX'
    'JCDwoNX2FsaWFzX3BsdXJhbA==');

@$core.Deprecated('Use postSettingsDescriptor instead')
const PostSettings$json = {
  '1': 'PostSettings',
  '2': [
    {'1': 'visible', '3': 1, '4': 1, '5': 8, '10': 'visible'},
    {'1': 'default_moderation', '3': 2, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'defaultModeration'},
    {'1': 'default_visibility', '3': 3, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'defaultVisibility'},
    {'1': 'alias_singular', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'aliasSingular', '17': true},
    {'1': 'alias_plural', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'aliasPlural', '17': true},
    {'1': 'enable_replies', '3': 6, '4': 1, '5': 8, '9': 2, '10': 'enableReplies', '17': true},
  ],
  '8': [
    {'1': '_alias_singular'},
    {'1': '_alias_plural'},
    {'1': '_enable_replies'},
  ],
};

/// Descriptor for `PostSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List postSettingsDescriptor = $convert.base64Decode(
    'CgxQb3N0U2V0dGluZ3MSGAoHdmlzaWJsZRgBIAEoCFIHdmlzaWJsZRJAChJkZWZhdWx0X21vZG'
    'VyYXRpb24YAiABKA4yES5yZWxsbS5Nb2RlcmF0aW9uUhFkZWZhdWx0TW9kZXJhdGlvbhJAChJk'
    'ZWZhdWx0X3Zpc2liaWxpdHkYAyABKA4yES5yZWxsbS5WaXNpYmlsaXR5UhFkZWZhdWx0VmlzaW'
    'JpbGl0eRIqCg5hbGlhc19zaW5ndWxhchgEIAEoCUgAUg1hbGlhc1Npbmd1bGFyiAEBEiYKDGFs'
    'aWFzX3BsdXJhbBgFIAEoCUgBUgthbGlhc1BsdXJhbIgBARIqCg5lbmFibGVfcmVwbGllcxgGIA'
    'EoCEgCUg1lbmFibGVSZXBsaWVziAEBQhEKD19hbGlhc19zaW5ndWxhckIPCg1fYWxpYXNfcGx1'
    'cmFsQhEKD19lbmFibGVfcmVwbGllcw==');

@$core.Deprecated('Use eventSettingsDescriptor instead')
const EventSettings$json = {
  '1': 'EventSettings',
  '2': [
    {'1': 'visible', '3': 1, '4': 1, '5': 8, '10': 'visible'},
    {'1': 'default_moderation', '3': 2, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'defaultModeration'},
    {'1': 'default_visibility', '3': 3, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'defaultVisibility'},
    {'1': 'alias_singular', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'aliasSingular', '17': true},
    {'1': 'alias_plural', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'aliasPlural', '17': true},
    {'1': 'enable_replies', '3': 6, '4': 1, '5': 8, '9': 2, '10': 'enableReplies', '17': true},
    {'1': 'calendar_lookback_days', '3': 7, '4': 1, '5': 13, '9': 3, '10': 'calendarLookbackDays', '17': true},
    {'1': 'default_calendar_display_mode', '3': 8, '4': 1, '5': 14, '6': '.rellm.CalendarDisplayMode', '10': 'defaultCalendarDisplayMode'},
    {'1': 'show_started_or_long_events_by_default', '3': 9, '4': 1, '5': 8, '10': 'showStartedOrLongEventsByDefault'},
  ],
  '8': [
    {'1': '_alias_singular'},
    {'1': '_alias_plural'},
    {'1': '_enable_replies'},
    {'1': '_calendar_lookback_days'},
  ],
};

/// Descriptor for `EventSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventSettingsDescriptor = $convert.base64Decode(
    'Cg1FdmVudFNldHRpbmdzEhgKB3Zpc2libGUYASABKAhSB3Zpc2libGUSQAoSZGVmYXVsdF9tb2'
    'RlcmF0aW9uGAIgASgOMhEucmVsbG0uTW9kZXJhdGlvblIRZGVmYXVsdE1vZGVyYXRpb24SQAoS'
    'ZGVmYXVsdF92aXNpYmlsaXR5GAMgASgOMhEucmVsbG0uVmlzaWJpbGl0eVIRZGVmYXVsdFZpc2'
    'liaWxpdHkSKgoOYWxpYXNfc2luZ3VsYXIYBCABKAlIAFINYWxpYXNTaW5ndWxhcogBARImCgxh'
    'bGlhc19wbHVyYWwYBSABKAlIAVILYWxpYXNQbHVyYWyIAQESKgoOZW5hYmxlX3JlcGxpZXMYBi'
    'ABKAhIAlINZW5hYmxlUmVwbGllc4gBARI5ChZjYWxlbmRhcl9sb29rYmFja19kYXlzGAcgASgN'
    'SANSFGNhbGVuZGFyTG9va2JhY2tEYXlziAEBEl0KHWRlZmF1bHRfY2FsZW5kYXJfZGlzcGxheV'
    '9tb2RlGAggASgOMhoucmVsbG0uQ2FsZW5kYXJEaXNwbGF5TW9kZVIaZGVmYXVsdENhbGVuZGFy'
    'RGlzcGxheU1vZGUSUAomc2hvd19zdGFydGVkX29yX2xvbmdfZXZlbnRzX2J5X2RlZmF1bHQYCS'
    'ABKAhSIHNob3dTdGFydGVkT3JMb25nRXZlbnRzQnlEZWZhdWx0QhEKD19hbGlhc19zaW5ndWxh'
    'ckIPCg1fYWxpYXNfcGx1cmFsQhEKD19lbmFibGVfcmVwbGllc0IZChdfY2FsZW5kYXJfbG9va2'
    'JhY2tfZGF5cw==');

@$core.Deprecated('Use serverInfoDescriptor instead')
const ServerInfo$json = {
  '1': 'ServerInfo',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'short_name', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'shortName', '17': true},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'description', '17': true},
    {'1': 'privacy_policy', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'privacyPolicy', '17': true},
    {'1': 'logo', '3': 5, '4': 1, '5': 11, '6': '.rellm.ServerLogo', '9': 4, '10': 'logo', '17': true},
    {'1': 'web_user_interface', '3': 6, '4': 1, '5': 14, '6': '.rellm.WebUserInterface', '9': 5, '10': 'webUserInterface', '17': true},
    {'1': 'colors', '3': 7, '4': 1, '5': 11, '6': '.rellm.ServerColors', '9': 6, '10': 'colors', '17': true},
    {'1': 'media_policy', '3': 8, '4': 1, '5': 9, '9': 7, '10': 'mediaPolicy', '17': true},
    {
      '1': 'recommended_server_hosts',
      '3': 9,
      '4': 3,
      '5': 9,
      '8': {'3': true},
      '10': 'recommendedServerHosts',
    },
  ],
  '8': [
    {'1': '_name'},
    {'1': '_short_name'},
    {'1': '_description'},
    {'1': '_privacy_policy'},
    {'1': '_logo'},
    {'1': '_web_user_interface'},
    {'1': '_colors'},
    {'1': '_media_policy'},
  ],
};

/// Descriptor for `ServerInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverInfoDescriptor = $convert.base64Decode(
    'CgpTZXJ2ZXJJbmZvEhcKBG5hbWUYASABKAlIAFIEbmFtZYgBARIiCgpzaG9ydF9uYW1lGAIgAS'
    'gJSAFSCXNob3J0TmFtZYgBARIlCgtkZXNjcmlwdGlvbhgDIAEoCUgCUgtkZXNjcmlwdGlvbogB'
    'ARIqCg5wcml2YWN5X3BvbGljeRgEIAEoCUgDUg1wcml2YWN5UG9saWN5iAEBEioKBGxvZ28YBS'
    'ABKAsyES5yZWxsbS5TZXJ2ZXJMb2dvSARSBGxvZ2+IAQESSgoSd2ViX3VzZXJfaW50ZXJmYWNl'
    'GAYgASgOMhcucmVsbG0uV2ViVXNlckludGVyZmFjZUgFUhB3ZWJVc2VySW50ZXJmYWNliAEBEj'
    'AKBmNvbG9ycxgHIAEoCzITLnJlbGxtLlNlcnZlckNvbG9yc0gGUgZjb2xvcnOIAQESJgoMbWVk'
    'aWFfcG9saWN5GAggASgJSAdSC21lZGlhUG9saWN5iAEBEjwKGHJlY29tbWVuZGVkX3NlcnZlcl'
    '9ob3N0cxgJIAMoCUICGAFSFnJlY29tbWVuZGVkU2VydmVySG9zdHNCBwoFX25hbWVCDQoLX3No'
    'b3J0X25hbWVCDgoMX2Rlc2NyaXB0aW9uQhEKD19wcml2YWN5X3BvbGljeUIHCgVfbG9nb0IVCh'
    'Nfd2ViX3VzZXJfaW50ZXJmYWNlQgkKB19jb2xvcnNCDwoNX21lZGlhX3BvbGljeQ==');

@$core.Deprecated('Use serverLogoDescriptor instead')
const ServerLogo$json = {
  '1': 'ServerLogo',
  '2': [
    {'1': 'squareMediaId', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'squareMediaId', '17': true},
    {'1': 'squareMediaIdDark', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'squareMediaIdDark', '17': true},
    {'1': 'wideMediaId', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'wideMediaId', '17': true},
    {'1': 'wideMediaIdDark', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'wideMediaIdDark', '17': true},
  ],
  '8': [
    {'1': '_squareMediaId'},
    {'1': '_squareMediaIdDark'},
    {'1': '_wideMediaId'},
    {'1': '_wideMediaIdDark'},
  ],
};

/// Descriptor for `ServerLogo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverLogoDescriptor = $convert.base64Decode(
    'CgpTZXJ2ZXJMb2dvEikKDXNxdWFyZU1lZGlhSWQYASABKAlIAFINc3F1YXJlTWVkaWFJZIgBAR'
    'IxChFzcXVhcmVNZWRpYUlkRGFyaxgCIAEoCUgBUhFzcXVhcmVNZWRpYUlkRGFya4gBARIlCgt3'
    'aWRlTWVkaWFJZBgDIAEoCUgCUgt3aWRlTWVkaWFJZIgBARItCg93aWRlTWVkaWFJZERhcmsYBC'
    'ABKAlIA1IPd2lkZU1lZGlhSWREYXJriAEBQhAKDl9zcXVhcmVNZWRpYUlkQhQKEl9zcXVhcmVN'
    'ZWRpYUlkRGFya0IOCgxfd2lkZU1lZGlhSWRCEgoQX3dpZGVNZWRpYUlkRGFyaw==');

@$core.Deprecated('Use customNavigationTabSetDescriptor instead')
const CustomNavigationTabSet$json = {
  '1': 'CustomNavigationTabSet',
  '2': [
    {'1': 'home', '3': 1, '4': 1, '5': 11, '6': '.rellm.CustomHomePage', '9': 0, '10': 'home', '17': true},
    {'1': 'tabs', '3': 2, '4': 3, '5': 11, '6': '.rellm.CustomNavigationTab', '10': 'tabs'},
    {'1': 'tab_style', '3': 3, '4': 1, '5': 14, '6': '.rellm.NavigationTabStyle', '10': 'tabStyle'},
  ],
  '8': [
    {'1': '_home'},
  ],
};

/// Descriptor for `CustomNavigationTabSet`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customNavigationTabSetDescriptor = $convert.base64Decode(
    'ChZDdXN0b21OYXZpZ2F0aW9uVGFiU2V0Ei4KBGhvbWUYASABKAsyFS5yZWxsbS5DdXN0b21Ib2'
    '1lUGFnZUgAUgRob21liAEBEi4KBHRhYnMYAiADKAsyGi5yZWxsbS5DdXN0b21OYXZpZ2F0aW9u'
    'VGFiUgR0YWJzEjYKCXRhYl9zdHlsZRgDIAEoDjIZLnJlbGxtLk5hdmlnYXRpb25UYWJTdHlsZV'
    'IIdGFiU3R5bGVCBwoFX2hvbWU=');

@$core.Deprecated('Use customHomePageDescriptor instead')
const CustomHomePage$json = {
  '1': 'CustomHomePage',
  '2': [
    {'1': 'tab', '3': 1, '4': 1, '5': 14, '6': '.rellm.NavigationTab', '9': 0, '10': 'tab'},
    {'1': 'post_id', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'postId'},
    {'1': 'pinned_post_ids', '3': 3, '4': 3, '5': 9, '10': 'pinnedPostIds'},
    {'1': 'show_events_strip', '3': 4, '4': 1, '5': 8, '10': 'showEventsStrip'},
    {'1': 'default_events_strip_to_row', '3': 5, '4': 1, '5': 8, '10': 'defaultEventsStripToRow'},
    {'1': 'default_events_strip_calendar_display_mode', '3': 6, '4': 1, '5': 14, '6': '.rellm.CalendarDisplayMode', '10': 'defaultEventsStripCalendarDisplayMode'},
  ],
  '8': [
    {'1': 'target'},
  ],
};

/// Descriptor for `CustomHomePage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customHomePageDescriptor = $convert.base64Decode(
    'Cg5DdXN0b21Ib21lUGFnZRIoCgN0YWIYASABKA4yFC5yZWxsbS5OYXZpZ2F0aW9uVGFiSABSA3'
    'RhYhIZCgdwb3N0X2lkGAIgASgJSABSBnBvc3RJZBImCg9waW5uZWRfcG9zdF9pZHMYAyADKAlS'
    'DXBpbm5lZFBvc3RJZHMSKgoRc2hvd19ldmVudHNfc3RyaXAYBCABKAhSD3Nob3dFdmVudHNTdH'
    'JpcBI8ChtkZWZhdWx0X2V2ZW50c19zdHJpcF90b19yb3cYBSABKAhSF2RlZmF1bHRFdmVudHNT'
    'dHJpcFRvUm93EnUKKmRlZmF1bHRfZXZlbnRzX3N0cmlwX2NhbGVuZGFyX2Rpc3BsYXlfbW9kZR'
    'gGIAEoDjIaLnJlbGxtLkNhbGVuZGFyRGlzcGxheU1vZGVSJWRlZmF1bHRFdmVudHNTdHJpcENh'
    'bGVuZGFyRGlzcGxheU1vZGVCCAoGdGFyZ2V0');

@$core.Deprecated('Use customNavigationTabDescriptor instead')
const CustomNavigationTab$json = {
  '1': 'CustomNavigationTab',
  '2': [
    {'1': 'tab', '3': 1, '4': 1, '5': 14, '6': '.rellm.NavigationTab', '9': 0, '10': 'tab'},
    {'1': 'post_id', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'postId'},
    {'1': 'is_profile', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'isProfile'},
    {'1': 'emoji_icon', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'emojiIcon'},
    {'1': 'icon_media_id', '3': 11, '4': 1, '5': 9, '9': 1, '10': 'iconMediaId'},
    {'1': 'title', '3': 12, '4': 1, '5': 9, '9': 2, '10': 'title', '17': true},
    {'1': 'path', '3': 13, '4': 1, '5': 9, '10': 'path'},
  ],
  '8': [
    {'1': 'target'},
    {'1': 'icon'},
    {'1': '_title'},
  ],
};

/// Descriptor for `CustomNavigationTab`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customNavigationTabDescriptor = $convert.base64Decode(
    'ChNDdXN0b21OYXZpZ2F0aW9uVGFiEigKA3RhYhgBIAEoDjIULnJlbGxtLk5hdmlnYXRpb25UYW'
    'JIAFIDdGFiEhkKB3Bvc3RfaWQYAiABKAlIAFIGcG9zdElkEh8KCmlzX3Byb2ZpbGUYAyABKAhI'
    'AFIJaXNQcm9maWxlEh8KCmVtb2ppX2ljb24YCiABKAlIAVIJZW1vamlJY29uEiQKDWljb25fbW'
    'VkaWFfaWQYCyABKAlIAVILaWNvbk1lZGlhSWQSGQoFdGl0bGUYDCABKAlIAlIFdGl0bGWIAQES'
    'EgoEcGF0aBgNIAEoCVIEcGF0aEIICgZ0YXJnZXRCBgoEaWNvbkIICgZfdGl0bGU=');

@$core.Deprecated('Use serverColorsDescriptor instead')
const ServerColors$json = {
  '1': 'ServerColors',
  '2': [
    {'1': 'primary', '3': 1, '4': 1, '5': 13, '9': 0, '10': 'primary', '17': true},
    {'1': 'navigation', '3': 2, '4': 1, '5': 13, '9': 1, '10': 'navigation', '17': true},
    {'1': 'author', '3': 3, '4': 1, '5': 13, '9': 2, '10': 'author', '17': true},
    {'1': 'admin', '3': 4, '4': 1, '5': 13, '9': 3, '10': 'admin', '17': true},
    {'1': 'moderator', '3': 5, '4': 1, '5': 13, '9': 4, '10': 'moderator', '17': true},
  ],
  '8': [
    {'1': '_primary'},
    {'1': '_navigation'},
    {'1': '_author'},
    {'1': '_admin'},
    {'1': '_moderator'},
  ],
};

/// Descriptor for `ServerColors`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverColorsDescriptor = $convert.base64Decode(
    'CgxTZXJ2ZXJDb2xvcnMSHQoHcHJpbWFyeRgBIAEoDUgAUgdwcmltYXJ5iAEBEiMKCm5hdmlnYX'
    'Rpb24YAiABKA1IAVIKbmF2aWdhdGlvbogBARIbCgZhdXRob3IYAyABKA1IAlIGYXV0aG9yiAEB'
    'EhkKBWFkbWluGAQgASgNSANSBWFkbWluiAEBEiEKCW1vZGVyYXRvchgFIAEoDUgEUgltb2Rlcm'
    'F0b3KIAQFCCgoIX3ByaW1hcnlCDQoLX25hdmlnYXRpb25CCQoHX2F1dGhvckIICgZfYWRtaW5C'
    'DAoKX21vZGVyYXRvcg==');

@$core.Deprecated('Use webPushConfigDescriptor instead')
const WebPushConfig$json = {
  '1': 'WebPushConfig',
  '2': [
    {'1': 'public_vapid_key', '3': 1, '4': 1, '5': 9, '10': 'publicVapidKey'},
    {'1': 'private_vapid_key', '3': 2, '4': 1, '5': 9, '10': 'privateVapidKey'},
  ],
};

/// Descriptor for `WebPushConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List webPushConfigDescriptor = $convert.base64Decode(
    'Cg1XZWJQdXNoQ29uZmlnEigKEHB1YmxpY192YXBpZF9rZXkYASABKAlSDnB1YmxpY1ZhcGlkS2'
    'V5EioKEXByaXZhdGVfdmFwaWRfa2V5GAIgASgJUg9wcml2YXRlVmFwaWRLZXk=');

@$core.Deprecated('Use twilioConfigDescriptor instead')
const TwilioConfig$json = {
  '1': 'TwilioConfig',
  '2': [
    {'1': 'twilio_enabled', '3': 1, '4': 1, '5': 8, '10': 'twilioEnabled'},
    {'1': 'twilio_account_sid', '3': 3, '4': 1, '5': 9, '10': 'twilioAccountSid'},
    {'1': 'twilio_api_key_sid', '3': 5, '4': 1, '5': 9, '10': 'twilioApiKeySid'},
    {'1': 'twilio_api_key_secret', '3': 2, '4': 1, '5': 9, '10': 'twilioApiKeySecret'},
    {'1': 'twilio_from_number', '3': 4, '4': 1, '5': 9, '10': 'twilioFromNumber'},
  ],
};

/// Descriptor for `TwilioConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List twilioConfigDescriptor = $convert.base64Decode(
    'CgxUd2lsaW9Db25maWcSJQoOdHdpbGlvX2VuYWJsZWQYASABKAhSDXR3aWxpb0VuYWJsZWQSLA'
    'oSdHdpbGlvX2FjY291bnRfc2lkGAMgASgJUhB0d2lsaW9BY2NvdW50U2lkEisKEnR3aWxpb19h'
    'cGlfa2V5X3NpZBgFIAEoCVIPdHdpbGlvQXBpS2V5U2lkEjEKFXR3aWxpb19hcGlfa2V5X3NlY3'
    'JldBgCIAEoCVISdHdpbGlvQXBpS2V5U2VjcmV0EiwKEnR3aWxpb19mcm9tX251bWJlchgEIAEo'
    'CVIQdHdpbGlvRnJvbU51bWJlcg==');

@$core.Deprecated('Use birdConfigDescriptor instead')
const BirdConfig$json = {
  '1': 'BirdConfig',
  '2': [
    {'1': 'bird_enabled', '3': 1, '4': 1, '5': 8, '10': 'birdEnabled'},
    {'1': 'bird_access_key', '3': 2, '4': 1, '5': 9, '10': 'birdAccessKey'},
    {'1': 'bird_from', '3': 3, '4': 1, '5': 9, '10': 'birdFrom'},
    {'1': 'bird_region', '3': 4, '4': 1, '5': 9, '10': 'birdRegion'},
  ],
};

/// Descriptor for `BirdConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List birdConfigDescriptor = $convert.base64Decode(
    'CgpCaXJkQ29uZmlnEiEKDGJpcmRfZW5hYmxlZBgBIAEoCFILYmlyZEVuYWJsZWQSJgoPYmlyZF'
    '9hY2Nlc3Nfa2V5GAIgASgJUg1iaXJkQWNjZXNzS2V5EhsKCWJpcmRfZnJvbRgDIAEoCVIIYmly'
    'ZEZyb20SHwoLYmlyZF9yZWdpb24YBCABKAlSCmJpcmRSZWdpb24=');

@$core.Deprecated('Use stripeConfigDescriptor instead')
const StripeConfig$json = {
  '1': 'StripeConfig',
  '2': [
    {'1': 'stripe_enabled', '3': 1, '4': 1, '5': 8, '10': 'stripeEnabled'},
    {'1': 'stripe_secret_key', '3': 2, '4': 1, '5': 9, '10': 'stripeSecretKey'},
    {'1': 'stripe_publishable_key', '3': 3, '4': 1, '5': 9, '10': 'stripePublishableKey'},
    {'1': 'stripe_webhook_signing_secret', '3': 4, '4': 1, '5': 9, '10': 'stripeWebhookSigningSecret'},
  ],
};

/// Descriptor for `StripeConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stripeConfigDescriptor = $convert.base64Decode(
    'CgxTdHJpcGVDb25maWcSJQoOc3RyaXBlX2VuYWJsZWQYASABKAhSDXN0cmlwZUVuYWJsZWQSKg'
    'oRc3RyaXBlX3NlY3JldF9rZXkYAiABKAlSD3N0cmlwZVNlY3JldEtleRI0ChZzdHJpcGVfcHVi'
    'bGlzaGFibGVfa2V5GAMgASgJUhRzdHJpcGVQdWJsaXNoYWJsZUtleRJBCh1zdHJpcGVfd2ViaG'
    '9va19zaWduaW5nX3NlY3JldBgEIAEoCVIac3RyaXBlV2ViaG9va1NpZ25pbmdTZWNyZXQ=');

