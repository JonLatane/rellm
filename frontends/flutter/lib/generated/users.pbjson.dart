//
//  Generated code. Do not modify.
//  source: users.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use contactConsentStateDescriptor instead')
const ContactConsentState$json = {
  '1': 'ContactConsentState',
  '2': [
    {'1': 'CONTACT_CONSENT_REVOKED', '2': 0},
    {'1': 'CONTACT_CONSENT_GRANTED', '2': 1},
  ],
};

/// Descriptor for `ContactConsentState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List contactConsentStateDescriptor = $convert.base64Decode(
    'ChNDb250YWN0Q29uc2VudFN0YXRlEhsKF0NPTlRBQ1RfQ09OU0VOVF9SRVZPS0VEEAASGwoXQ0'
    '9OVEFDVF9DT05TRU5UX0dSQU5URUQQAQ==');

@$core.Deprecated('Use userListingTypeDescriptor instead')
const UserListingType$json = {
  '1': 'UserListingType',
  '2': [
    {'1': 'EVERYONE', '2': 0},
    {'1': 'FOLLOWING', '2': 1},
    {'1': 'FRIENDS', '2': 2},
    {'1': 'FOLLOWERS', '2': 3},
    {'1': 'FOLLOW_REQUESTS', '2': 4},
    {'1': 'USERS_TEXT_SEARCH', '2': 5},
    {'1': 'FOLLOWERS_TEXT_SEARCH', '2': 6},
    {'1': 'FOLLOWING_TEXT_SEARCH', '2': 7},
    {'1': 'FRIENDS_TEXT_SEARCH', '2': 8},
    {'1': 'FOLLOW_REQUESTS_TEXT_SEARCH', '2': 9},
    {'1': 'ADMINS', '2': 10},
  ],
};

/// Descriptor for `UserListingType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List userListingTypeDescriptor = $convert.base64Decode(
    'Cg9Vc2VyTGlzdGluZ1R5cGUSDAoIRVZFUllPTkUQABINCglGT0xMT1dJTkcQARILCgdGUklFTk'
    'RTEAISDQoJRk9MTE9XRVJTEAMSEwoPRk9MTE9XX1JFUVVFU1RTEAQSFQoRVVNFUlNfVEVYVF9T'
    'RUFSQ0gQBRIZChVGT0xMT1dFUlNfVEVYVF9TRUFSQ0gQBhIZChVGT0xMT1dJTkdfVEVYVF9TRU'
    'FSQ0gQBxIXChNGUklFTkRTX1RFWFRfU0VBUkNIEAgSHwobRk9MTE9XX1JFUVVFU1RTX1RFWFRf'
    'U0VBUkNIEAkSCgoGQURNSU5TEAo=');

@$core.Deprecated('Use userDescriptor instead')
const User$json = {
  '1': 'User',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'real_name', '3': 3, '4': 1, '5': 9, '10': 'realName'},
    {'1': 'email', '3': 4, '4': 1, '5': 11, '6': '.rellm.ContactMethod', '9': 0, '10': 'email', '17': true},
    {'1': 'phone', '3': 5, '4': 1, '5': 11, '6': '.rellm.ContactMethod', '9': 1, '10': 'phone', '17': true},
    {'1': 'permissions', '3': 6, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'permissions'},
    {'1': 'avatar', '3': 7, '4': 1, '5': 11, '6': '.rellm.MediaReference', '9': 2, '10': 'avatar', '17': true},
    {'1': 'bio', '3': 8, '4': 1, '5': 9, '10': 'bio'},
    {'1': 'media_storage_limit_bytes', '3': 10, '4': 1, '5': 4, '9': 3, '10': 'mediaStorageLimitBytes', '17': true},
    {'1': 'media_storage_bytes_used', '3': 11, '4': 1, '5': 4, '10': 'mediaStorageBytesUsed'},
    {'1': 'visibility', '3': 20, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'visibility'},
    {'1': 'moderation', '3': 21, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'moderation'},
    {'1': 'default_follow_moderation', '3': 30, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'defaultFollowModeration'},
    {'1': 'follower_count', '3': 31, '4': 1, '5': 5, '9': 4, '10': 'followerCount', '17': true},
    {'1': 'following_count', '3': 32, '4': 1, '5': 5, '9': 5, '10': 'followingCount', '17': true},
    {'1': 'friend_count', '3': 33, '4': 1, '5': 5, '9': 6, '10': 'friendCount', '17': true},
    {'1': 'group_count', '3': 34, '4': 1, '5': 5, '9': 7, '10': 'groupCount', '17': true},
    {'1': 'post_count', '3': 35, '4': 1, '5': 5, '9': 8, '10': 'postCount', '17': true},
    {'1': 'response_count', '3': 36, '4': 1, '5': 5, '9': 9, '10': 'responseCount', '17': true},
    {'1': 'event_count', '3': 37, '4': 1, '5': 5, '9': 10, '10': 'eventCount', '17': true},
    {'1': 'occasion_count', '3': 38, '4': 1, '5': 5, '9': 11, '10': 'occasionCount', '17': true},
    {'1': 'current_user_follow', '3': 50, '4': 1, '5': 11, '6': '.rellm.Follow', '9': 12, '10': 'currentUserFollow', '17': true},
    {'1': 'target_current_user_follow', '3': 51, '4': 1, '5': 11, '6': '.rellm.Follow', '9': 13, '10': 'targetCurrentUserFollow', '17': true},
    {'1': 'current_group_membership', '3': 52, '4': 1, '5': 11, '6': '.rellm.Membership', '9': 14, '10': 'currentGroupMembership', '17': true},
    {'1': 'federated_profiles', '3': 81, '4': 3, '5': 11, '6': '.rellm.FederatedAccount', '10': 'federatedProfiles'},
    {'1': 'sync_destinations', '3': 82, '4': 3, '5': 11, '6': '.rellm.SyncDestination', '10': 'syncDestinations'},
    {'1': 'sync_sources', '3': 83, '4': 3, '5': 11, '6': '.rellm.SyncSource', '10': 'syncSources'},
    {'1': 'ai_models', '3': 84, '4': 3, '5': 11, '6': '.rellm.AIModel', '10': 'aiModels'},
    {'1': 'market_subscriptions', '3': 85, '4': 3, '5': 11, '6': '.rellm.MarketSubscription', '10': 'marketSubscriptions'},
    {'1': 'created_at', '3': 100, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 101, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 15, '10': 'updatedAt', '17': true},
  ],
  '8': [
    {'1': '_email'},
    {'1': '_phone'},
    {'1': '_avatar'},
    {'1': '_media_storage_limit_bytes'},
    {'1': '_follower_count'},
    {'1': '_following_count'},
    {'1': '_friend_count'},
    {'1': '_group_count'},
    {'1': '_post_count'},
    {'1': '_response_count'},
    {'1': '_event_count'},
    {'1': '_occasion_count'},
    {'1': '_current_user_follow'},
    {'1': '_target_current_user_follow'},
    {'1': '_current_group_membership'},
    {'1': '_updated_at'},
  ],
};

/// Descriptor for `User`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userDescriptor = $convert.base64Decode(
    'CgRVc2VyEg4KAmlkGAEgASgJUgJpZBIaCgh1c2VybmFtZRgCIAEoCVIIdXNlcm5hbWUSGwoJcm'
    'VhbF9uYW1lGAMgASgJUghyZWFsTmFtZRIvCgVlbWFpbBgEIAEoCzIULnJlbGxtLkNvbnRhY3RN'
    'ZXRob2RIAFIFZW1haWyIAQESLwoFcGhvbmUYBSABKAsyFC5yZWxsbS5Db250YWN0TWV0aG9kSA'
    'FSBXBob25liAEBEjMKC3Blcm1pc3Npb25zGAYgAygOMhEucmVsbG0uUGVybWlzc2lvblILcGVy'
    'bWlzc2lvbnMSMgoGYXZhdGFyGAcgASgLMhUucmVsbG0uTWVkaWFSZWZlcmVuY2VIAlIGYXZhdG'
    'FyiAEBEhAKA2JpbxgIIAEoCVIDYmlvEj4KGW1lZGlhX3N0b3JhZ2VfbGltaXRfYnl0ZXMYCiAB'
    'KARIA1IWbWVkaWFTdG9yYWdlTGltaXRCeXRlc4gBARI3ChhtZWRpYV9zdG9yYWdlX2J5dGVzX3'
    'VzZWQYCyABKARSFW1lZGlhU3RvcmFnZUJ5dGVzVXNlZBIxCgp2aXNpYmlsaXR5GBQgASgOMhEu'
    'cmVsbG0uVmlzaWJpbGl0eVIKdmlzaWJpbGl0eRIxCgptb2RlcmF0aW9uGBUgASgOMhEucmVsbG'
    '0uTW9kZXJhdGlvblIKbW9kZXJhdGlvbhJNChlkZWZhdWx0X2ZvbGxvd19tb2RlcmF0aW9uGB4g'
    'ASgOMhEucmVsbG0uTW9kZXJhdGlvblIXZGVmYXVsdEZvbGxvd01vZGVyYXRpb24SKgoOZm9sbG'
    '93ZXJfY291bnQYHyABKAVIBFINZm9sbG93ZXJDb3VudIgBARIsCg9mb2xsb3dpbmdfY291bnQY'
    'ICABKAVIBVIOZm9sbG93aW5nQ291bnSIAQESJgoMZnJpZW5kX2NvdW50GCEgASgFSAZSC2ZyaW'
    'VuZENvdW50iAEBEiQKC2dyb3VwX2NvdW50GCIgASgFSAdSCmdyb3VwQ291bnSIAQESIgoKcG9z'
    'dF9jb3VudBgjIAEoBUgIUglwb3N0Q291bnSIAQESKgoOcmVzcG9uc2VfY291bnQYJCABKAVICV'
    'INcmVzcG9uc2VDb3VudIgBARIkCgtldmVudF9jb3VudBglIAEoBUgKUgpldmVudENvdW50iAEB'
    'EioKDm9jY2FzaW9uX2NvdW50GCYgASgFSAtSDW9jY2FzaW9uQ291bnSIAQESQgoTY3VycmVudF'
    '91c2VyX2ZvbGxvdxgyIAEoCzINLnJlbGxtLkZvbGxvd0gMUhFjdXJyZW50VXNlckZvbGxvd4gB'
    'ARJPChp0YXJnZXRfY3VycmVudF91c2VyX2ZvbGxvdxgzIAEoCzINLnJlbGxtLkZvbGxvd0gNUh'
    'd0YXJnZXRDdXJyZW50VXNlckZvbGxvd4gBARJQChhjdXJyZW50X2dyb3VwX21lbWJlcnNoaXAY'
    'NCABKAsyES5yZWxsbS5NZW1iZXJzaGlwSA5SFmN1cnJlbnRHcm91cE1lbWJlcnNoaXCIAQESRg'
    'oSZmVkZXJhdGVkX3Byb2ZpbGVzGFEgAygLMhcucmVsbG0uRmVkZXJhdGVkQWNjb3VudFIRZmVk'
    'ZXJhdGVkUHJvZmlsZXMSQwoRc3luY19kZXN0aW5hdGlvbnMYUiADKAsyFi5yZWxsbS5TeW5jRG'
    'VzdGluYXRpb25SEHN5bmNEZXN0aW5hdGlvbnMSNAoMc3luY19zb3VyY2VzGFMgAygLMhEucmVs'
    'bG0uU3luY1NvdXJjZVILc3luY1NvdXJjZXMSKwoJYWlfbW9kZWxzGFQgAygLMg4ucmVsbG0uQU'
    'lNb2RlbFIIYWlNb2RlbHMSTAoUbWFya2V0X3N1YnNjcmlwdGlvbnMYVSADKAsyGS5yZWxsbS5N'
    'YXJrZXRTdWJzY3JpcHRpb25SE21hcmtldFN1YnNjcmlwdGlvbnMSOQoKY3JlYXRlZF9hdBhkIA'
    'EoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCWNyZWF0ZWRBdBI+Cgp1cGRhdGVkX2F0'
    'GGUgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcEgPUgl1cGRhdGVkQXSIAQFCCAoGX2'
    'VtYWlsQggKBl9waG9uZUIJCgdfYXZhdGFyQhwKGl9tZWRpYV9zdG9yYWdlX2xpbWl0X2J5dGVz'
    'QhEKD19mb2xsb3dlcl9jb3VudEISChBfZm9sbG93aW5nX2NvdW50Qg8KDV9mcmllbmRfY291bn'
    'RCDgoMX2dyb3VwX2NvdW50Qg0KC19wb3N0X2NvdW50QhEKD19yZXNwb25zZV9jb3VudEIOCgxf'
    'ZXZlbnRfY291bnRCEQoPX29jY2FzaW9uX2NvdW50QhYKFF9jdXJyZW50X3VzZXJfZm9sbG93Qh'
    '0KG190YXJnZXRfY3VycmVudF91c2VyX2ZvbGxvd0IbChlfY3VycmVudF9ncm91cF9tZW1iZXJz'
    'aGlwQg0KC191cGRhdGVkX2F0');

@$core.Deprecated('Use followDescriptor instead')
const Follow$json = {
  '1': 'Follow',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'target_user_id', '3': 2, '4': 1, '5': 9, '10': 'targetUserId'},
    {'1': 'target_user_moderation', '3': 3, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'targetUserModeration'},
    {'1': 'created_at', '3': 4, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'updatedAt', '17': true},
  ],
  '8': [
    {'1': '_updated_at'},
  ],
};

/// Descriptor for `Follow`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List followDescriptor = $convert.base64Decode(
    'CgZGb2xsb3cSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEiQKDnRhcmdldF91c2VyX2lkGAIgAS'
    'gJUgx0YXJnZXRVc2VySWQSRwoWdGFyZ2V0X3VzZXJfbW9kZXJhdGlvbhgDIAEoDjIRLnJlbGxt'
    'Lk1vZGVyYXRpb25SFHRhcmdldFVzZXJNb2RlcmF0aW9uEjkKCmNyZWF0ZWRfYXQYBCABKAsyGi'
    '5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVkQXQSPgoKdXBkYXRlZF9hdBgFIAEo'
    'CzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAFIJdXBkYXRlZEF0iAEBQg0KC191cGRhdG'
    'VkX2F0');

@$core.Deprecated('Use membershipDescriptor instead')
const Membership$json = {
  '1': 'Membership',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'group_id', '3': 2, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'permissions', '3': 3, '4': 3, '5': 14, '6': '.rellm.Permission', '10': 'permissions'},
    {'1': 'group_moderation', '3': 4, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'groupModeration'},
    {'1': 'user_moderation', '3': 5, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'userModeration'},
    {'1': 'created_at', '3': 6, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 7, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'updatedAt', '17': true},
  ],
  '8': [
    {'1': '_updated_at'},
  ],
};

/// Descriptor for `Membership`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List membershipDescriptor = $convert.base64Decode(
    'CgpNZW1iZXJzaGlwEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBIZCghncm91cF9pZBgCIAEoCV'
    'IHZ3JvdXBJZBIzCgtwZXJtaXNzaW9ucxgDIAMoDjIRLnJlbGxtLlBlcm1pc3Npb25SC3Blcm1p'
    'c3Npb25zEjwKEGdyb3VwX21vZGVyYXRpb24YBCABKA4yES5yZWxsbS5Nb2RlcmF0aW9uUg9ncm'
    '91cE1vZGVyYXRpb24SOgoPdXNlcl9tb2RlcmF0aW9uGAUgASgOMhEucmVsbG0uTW9kZXJhdGlv'
    'blIOdXNlck1vZGVyYXRpb24SOQoKY3JlYXRlZF9hdBgGIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi'
    '5UaW1lc3RhbXBSCWNyZWF0ZWRBdBI+Cgp1cGRhdGVkX2F0GAcgASgLMhouZ29vZ2xlLnByb3Rv'
    'YnVmLlRpbWVzdGFtcEgAUgl1cGRhdGVkQXSIAQFCDQoLX3VwZGF0ZWRfYXQ=');

@$core.Deprecated('Use contactMethodDescriptor instead')
const ContactMethod$json = {
  '1': 'ContactMethod',
  '2': [
    {'1': 'value', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'value', '17': true},
    {'1': 'visibility', '3': 2, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'visibility'},
    {'1': 'supported_by_server', '3': 3, '4': 1, '5': 8, '10': 'supportedByServer'},
    {'1': 'verified_at', '3': 4, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'verifiedAt', '17': true},
    {'1': 'verification_in_progress', '3': 5, '4': 1, '5': 11, '6': '.rellm.ContactMethodVerification', '9': 2, '10': 'verificationInProgress', '17': true},
    {'1': 'consent_state', '3': 6, '4': 1, '5': 14, '6': '.rellm.ContactConsentState', '10': 'consentState'},
    {'1': 'consent_history', '3': 7, '4': 3, '5': 11, '6': '.rellm.ContactConsentChange', '10': 'consentHistory'},
  ],
  '8': [
    {'1': '_value'},
    {'1': '_verified_at'},
    {'1': '_verification_in_progress'},
  ],
};

/// Descriptor for `ContactMethod`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactMethodDescriptor = $convert.base64Decode(
    'Cg1Db250YWN0TWV0aG9kEhkKBXZhbHVlGAEgASgJSABSBXZhbHVliAEBEjEKCnZpc2liaWxpdH'
    'kYAiABKA4yES5yZWxsbS5WaXNpYmlsaXR5Ugp2aXNpYmlsaXR5Ei4KE3N1cHBvcnRlZF9ieV9z'
    'ZXJ2ZXIYAyABKAhSEXN1cHBvcnRlZEJ5U2VydmVyEkAKC3ZlcmlmaWVkX2F0GAQgASgLMhouZ2'
    '9vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcEgBUgp2ZXJpZmllZEF0iAEBEl8KGHZlcmlmaWNhdGlv'
    'bl9pbl9wcm9ncmVzcxgFIAEoCzIgLnJlbGxtLkNvbnRhY3RNZXRob2RWZXJpZmljYXRpb25IAl'
    'IWdmVyaWZpY2F0aW9uSW5Qcm9ncmVzc4gBARI/Cg1jb25zZW50X3N0YXRlGAYgASgOMhoucmVs'
    'bG0uQ29udGFjdENvbnNlbnRTdGF0ZVIMY29uc2VudFN0YXRlEkQKD2NvbnNlbnRfaGlzdG9yeR'
    'gHIAMoCzIbLnJlbGxtLkNvbnRhY3RDb25zZW50Q2hhbmdlUg5jb25zZW50SGlzdG9yeUIICgZf'
    'dmFsdWVCDgoMX3ZlcmlmaWVkX2F0QhsKGV92ZXJpZmljYXRpb25faW5fcHJvZ3Jlc3M=');

@$core.Deprecated('Use contactConsentChangeDescriptor instead')
const ContactConsentChange$json = {
  '1': 'ContactConsentChange',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 14, '6': '.rellm.ContactConsentState', '10': 'state'},
    {'1': 'changed_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'changedAt'},
  ],
};

/// Descriptor for `ContactConsentChange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactConsentChangeDescriptor = $convert.base64Decode(
    'ChRDb250YWN0Q29uc2VudENoYW5nZRIwCgVzdGF0ZRgBIAEoDjIaLnJlbGxtLkNvbnRhY3RDb2'
    '5zZW50U3RhdGVSBXN0YXRlEjkKCmNoYW5nZWRfYXQYAiABKAsyGi5nb29nbGUucHJvdG9idWYu'
    'VGltZXN0YW1wUgljaGFuZ2VkQXQ=');

@$core.Deprecated('Use contactMethodVerificationDescriptor instead')
const ContactMethodVerification$json = {
  '1': 'ContactMethodVerification',
  '2': [
    {'1': 'verification_code', '3': 1, '4': 1, '5': 9, '10': 'verificationCode'},
    {'1': 'verification_started_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'verificationStartedAt'},
    {'1': 'attempts', '3': 3, '4': 1, '5': 5, '10': 'attempts'},
  ],
};

/// Descriptor for `ContactMethodVerification`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactMethodVerificationDescriptor = $convert.base64Decode(
    'ChlDb250YWN0TWV0aG9kVmVyaWZpY2F0aW9uEisKEXZlcmlmaWNhdGlvbl9jb2RlGAEgASgJUh'
    'B2ZXJpZmljYXRpb25Db2RlElIKF3ZlcmlmaWNhdGlvbl9zdGFydGVkX2F0GAIgASgLMhouZ29v'
    'Z2xlLnByb3RvYnVmLlRpbWVzdGFtcFIVdmVyaWZpY2F0aW9uU3RhcnRlZEF0EhoKCGF0dGVtcH'
    'RzGAMgASgFUghhdHRlbXB0cw==');

@$core.Deprecated('Use getUsersRequestDescriptor instead')
const GetUsersRequest$json = {
  '1': 'GetUsersRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'username', '17': true},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'userId', '17': true},
    {'1': 'search_text', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'searchText', '17': true},
    {'1': 'page', '3': 99, '4': 1, '5': 5, '9': 3, '10': 'page', '17': true},
    {'1': 'listing_type', '3': 100, '4': 1, '5': 14, '6': '.rellm.UserListingType', '10': 'listingType'},
  ],
  '8': [
    {'1': '_username'},
    {'1': '_user_id'},
    {'1': '_search_text'},
    {'1': '_page'},
  ],
};

/// Descriptor for `GetUsersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getUsersRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRVc2Vyc1JlcXVlc3QSHwoIdXNlcm5hbWUYASABKAlIAFIIdXNlcm5hbWWIAQESHAoHdX'
    'Nlcl9pZBgCIAEoCUgBUgZ1c2VySWSIAQESJAoLc2VhcmNoX3RleHQYAyABKAlIAlIKc2VhcmNo'
    'VGV4dIgBARIXCgRwYWdlGGMgASgFSANSBHBhZ2WIAQESOQoMbGlzdGluZ190eXBlGGQgASgOMh'
    'YucmVsbG0uVXNlckxpc3RpbmdUeXBlUgtsaXN0aW5nVHlwZUILCglfdXNlcm5hbWVCCgoIX3Vz'
    'ZXJfaWRCDgoMX3NlYXJjaF90ZXh0QgcKBV9wYWdl');

@$core.Deprecated('Use getUsersResponseDescriptor instead')
const GetUsersResponse$json = {
  '1': 'GetUsersResponse',
  '2': [
    {'1': 'users', '3': 1, '4': 3, '5': 11, '6': '.rellm.User', '10': 'users'},
    {'1': 'has_next_page', '3': 2, '4': 1, '5': 8, '10': 'hasNextPage'},
  ],
};

/// Descriptor for `GetUsersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getUsersResponseDescriptor = $convert.base64Decode(
    'ChBHZXRVc2Vyc1Jlc3BvbnNlEiEKBXVzZXJzGAEgAygLMgsucmVsbG0uVXNlclIFdXNlcnMSIg'
    'oNaGFzX25leHRfcGFnZRgCIAEoCFILaGFzTmV4dFBhZ2U=');

@$core.Deprecated('Use verifyContactMethodRequestDescriptor instead')
const VerifyContactMethodRequest$json = {
  '1': 'VerifyContactMethodRequest',
  '2': [
    {'1': 'value', '3': 1, '4': 1, '5': 9, '10': 'value'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '10': 'code'},
  ],
};

/// Descriptor for `VerifyContactMethodRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyContactMethodRequestDescriptor = $convert.base64Decode(
    'ChpWZXJpZnlDb250YWN0TWV0aG9kUmVxdWVzdBIUCgV2YWx1ZRgBIAEoCVIFdmFsdWUSEgoEY2'
    '9kZRgCIAEoCVIEY29kZQ==');

