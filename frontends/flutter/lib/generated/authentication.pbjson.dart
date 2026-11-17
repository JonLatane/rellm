//
//  Generated code. Do not modify.
//  source: authentication.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use createAccountRequestDescriptor instead')
const CreateAccountRequest$json = {
  '1': 'CreateAccountRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {'1': 'email', '3': 3, '4': 1, '5': 11, '6': '.rellm.ContactMethod', '9': 0, '10': 'email', '17': true},
    {'1': 'phone', '3': 4, '4': 1, '5': 11, '6': '.rellm.ContactMethod', '9': 1, '10': 'phone', '17': true},
    {'1': 'expires_at', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 2, '10': 'expiresAt', '17': true},
    {'1': 'device_name', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'deviceName', '17': true},
    {'1': 'phone_verification_code', '3': 7, '4': 1, '5': 9, '9': 4, '10': 'phoneVerificationCode', '17': true},
    {'1': 'email_verification_code', '3': 8, '4': 1, '5': 9, '9': 5, '10': 'emailVerificationCode', '17': true},
  ],
  '8': [
    {'1': '_email'},
    {'1': '_phone'},
    {'1': '_expires_at'},
    {'1': '_device_name'},
    {'1': '_phone_verification_code'},
    {'1': '_email_verification_code'},
  ],
};

/// Descriptor for `CreateAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createAccountRequestDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVBY2NvdW50UmVxdWVzdBIaCgh1c2VybmFtZRgBIAEoCVIIdXNlcm5hbWUSGgoIcG'
    'Fzc3dvcmQYAiABKAlSCHBhc3N3b3JkEi8KBWVtYWlsGAMgASgLMhQucmVsbG0uQ29udGFjdE1l'
    'dGhvZEgAUgVlbWFpbIgBARIvCgVwaG9uZRgEIAEoCzIULnJlbGxtLkNvbnRhY3RNZXRob2RIAV'
    'IFcGhvbmWIAQESPgoKZXhwaXJlc19hdBgFIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3Rh'
    'bXBIAlIJZXhwaXJlc0F0iAEBEiQKC2RldmljZV9uYW1lGAYgASgJSANSCmRldmljZU5hbWWIAQ'
    'ESOwoXcGhvbmVfdmVyaWZpY2F0aW9uX2NvZGUYByABKAlIBFIVcGhvbmVWZXJpZmljYXRpb25D'
    'b2RliAEBEjsKF2VtYWlsX3ZlcmlmaWNhdGlvbl9jb2RlGAggASgJSAVSFWVtYWlsVmVyaWZpY2'
    'F0aW9uQ29kZYgBAUIICgZfZW1haWxCCAoGX3Bob25lQg0KC19leHBpcmVzX2F0Qg4KDF9kZXZp'
    'Y2VfbmFtZUIaChhfcGhvbmVfdmVyaWZpY2F0aW9uX2NvZGVCGgoYX2VtYWlsX3ZlcmlmaWNhdG'
    'lvbl9jb2Rl');

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'username_password', '3': 1, '4': 1, '5': 11, '6': '.rellm.UsernamePasswordLoginRequest', '9': 0, '10': 'usernamePassword'},
    {'1': 'sms', '3': 2, '4': 1, '5': 11, '6': '.rellm.SMSLoginRequest', '9': 0, '10': 'sms'},
    {'1': 'email', '3': 3, '4': 1, '5': 11, '6': '.rellm.EmailLoginRequest', '9': 0, '10': 'email'},
  ],
  '8': [
    {'1': 'request'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSUgoRdXNlcm5hbWVfcGFzc3dvcmQYASABKAsyIy5yZWxsbS5Vc2Vybm'
    'FtZVBhc3N3b3JkTG9naW5SZXF1ZXN0SABSEHVzZXJuYW1lUGFzc3dvcmQSKgoDc21zGAIgASgL'
    'MhYucmVsbG0uU01TTG9naW5SZXF1ZXN0SABSA3NtcxIwCgVlbWFpbBgDIAEoCzIYLnJlbGxtLk'
    'VtYWlsTG9naW5SZXF1ZXN0SABSBWVtYWlsQgkKB3JlcXVlc3Q=');

@$core.Deprecated('Use usernamePasswordLoginRequestDescriptor instead')
const UsernamePasswordLoginRequest$json = {
  '1': 'UsernamePasswordLoginRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {'1': 'expires_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'expiresAt', '17': true},
    {'1': 'device_name', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'deviceName', '17': true},
    {'1': 'user_id', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'userId', '17': true},
  ],
  '8': [
    {'1': '_expires_at'},
    {'1': '_device_name'},
    {'1': '_user_id'},
  ],
};

/// Descriptor for `UsernamePasswordLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List usernamePasswordLoginRequestDescriptor = $convert.base64Decode(
    'ChxVc2VybmFtZVBhc3N3b3JkTG9naW5SZXF1ZXN0EhoKCHVzZXJuYW1lGAEgASgJUgh1c2Vybm'
    'FtZRIaCghwYXNzd29yZBgCIAEoCVIIcGFzc3dvcmQSPgoKZXhwaXJlc19hdBgDIAEoCzIaLmdv'
    'b2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAFIJZXhwaXJlc0F0iAEBEiQKC2RldmljZV9uYW1lGA'
    'QgASgJSAFSCmRldmljZU5hbWWIAQESHAoHdXNlcl9pZBgFIAEoCUgCUgZ1c2VySWSIAQFCDQoL'
    'X2V4cGlyZXNfYXRCDgoMX2RldmljZV9uYW1lQgoKCF91c2VyX2lk');

@$core.Deprecated('Use sMSLoginRequestDescriptor instead')
const SMSLoginRequest$json = {
  '1': 'SMSLoginRequest',
  '2': [
    {'1': 'phone_number', '3': 1, '4': 1, '5': 9, '10': 'phoneNumber'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'code', '17': true},
    {'1': 'expires_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'expiresAt', '17': true},
    {'1': 'device_name', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'deviceName', '17': true},
    {'1': 'user_id', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'userId', '17': true},
    {'1': 'consent_to_contact', '3': 6, '4': 1, '5': 8, '10': 'consentToContact'},
  ],
  '8': [
    {'1': '_code'},
    {'1': '_expires_at'},
    {'1': '_device_name'},
    {'1': '_user_id'},
  ],
};

/// Descriptor for `SMSLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sMSLoginRequestDescriptor = $convert.base64Decode(
    'Cg9TTVNMb2dpblJlcXVlc3QSIQoMcGhvbmVfbnVtYmVyGAEgASgJUgtwaG9uZU51bWJlchIXCg'
    'Rjb2RlGAIgASgJSABSBGNvZGWIAQESPgoKZXhwaXJlc19hdBgDIAEoCzIaLmdvb2dsZS5wcm90'
    'b2J1Zi5UaW1lc3RhbXBIAVIJZXhwaXJlc0F0iAEBEiQKC2RldmljZV9uYW1lGAQgASgJSAJSCm'
    'RldmljZU5hbWWIAQESHAoHdXNlcl9pZBgFIAEoCUgDUgZ1c2VySWSIAQESLAoSY29uc2VudF90'
    'b19jb250YWN0GAYgASgIUhBjb25zZW50VG9Db250YWN0QgcKBV9jb2RlQg0KC19leHBpcmVzX2'
    'F0Qg4KDF9kZXZpY2VfbmFtZUIKCghfdXNlcl9pZA==');

@$core.Deprecated('Use emailLoginRequestDescriptor instead')
const EmailLoginRequest$json = {
  '1': 'EmailLoginRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'code', '17': true},
    {'1': 'expires_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 1, '10': 'expiresAt', '17': true},
    {'1': 'device_name', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'deviceName', '17': true},
    {'1': 'user_id', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'userId', '17': true},
    {'1': 'consent_to_contact', '3': 6, '4': 1, '5': 8, '10': 'consentToContact'},
  ],
  '8': [
    {'1': '_code'},
    {'1': '_expires_at'},
    {'1': '_device_name'},
    {'1': '_user_id'},
  ],
};

/// Descriptor for `EmailLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emailLoginRequestDescriptor = $convert.base64Decode(
    'ChFFbWFpbExvZ2luUmVxdWVzdBIUCgVlbWFpbBgBIAEoCVIFZW1haWwSFwoEY29kZRgCIAEoCU'
    'gAUgRjb2RliAEBEj4KCmV4cGlyZXNfYXQYAyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0'
    'YW1wSAFSCWV4cGlyZXNBdIgBARIkCgtkZXZpY2VfbmFtZRgEIAEoCUgCUgpkZXZpY2VOYW1liA'
    'EBEhwKB3VzZXJfaWQYBSABKAlIA1IGdXNlcklkiAEBEiwKEmNvbnNlbnRfdG9fY29udGFjdBgG'
    'IAEoCFIQY29uc2VudFRvQ29udGFjdEIHCgVfY29kZUINCgtfZXhwaXJlc19hdEIOCgxfZGV2aW'
    'NlX25hbWVCCgoIX3VzZXJfaWQ=');

@$core.Deprecated('Use createThirdPartyRefreshTokenRequestDescriptor instead')
const CreateThirdPartyRefreshTokenRequest$json = {
  '1': 'CreateThirdPartyRefreshTokenRequest',
  '2': [
    {'1': 'expires_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'expiresAt', '17': true},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'device_name', '3': 4, '4': 1, '5': 9, '10': 'deviceName'},
  ],
  '8': [
    {'1': '_expires_at'},
  ],
};

/// Descriptor for `CreateThirdPartyRefreshTokenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createThirdPartyRefreshTokenRequestDescriptor = $convert.base64Decode(
    'CiNDcmVhdGVUaGlyZFBhcnR5UmVmcmVzaFRva2VuUmVxdWVzdBI+CgpleHBpcmVzX2F0GAIgAS'
    'gLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcEgAUglleHBpcmVzQXSIAQESFwoHdXNlcl9p'
    'ZBgDIAEoCVIGdXNlcklkEh8KC2RldmljZV9uYW1lGAQgASgJUgpkZXZpY2VOYW1lQg0KC19leH'
    'BpcmVzX2F0');

@$core.Deprecated('Use refreshTokenResponseDescriptor instead')
const RefreshTokenResponse$json = {
  '1': 'RefreshTokenResponse',
  '2': [
    {'1': 'refresh_token', '3': 1, '4': 1, '5': 11, '6': '.rellm.ExpirableToken', '10': 'refreshToken'},
    {'1': 'access_token', '3': 2, '4': 1, '5': 11, '6': '.rellm.ExpirableToken', '10': 'accessToken'},
    {'1': 'user', '3': 3, '4': 1, '5': 11, '6': '.rellm.User', '10': 'user'},
    {'1': 'verification_challenge', '3': 4, '4': 1, '5': 11, '6': '.rellm.VerificationChallenge', '9': 0, '10': 'verificationChallenge', '17': true},
  ],
  '8': [
    {'1': '_verification_challenge'},
  ],
};

/// Descriptor for `RefreshTokenResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List refreshTokenResponseDescriptor = $convert.base64Decode(
    'ChRSZWZyZXNoVG9rZW5SZXNwb25zZRI6Cg1yZWZyZXNoX3Rva2VuGAEgASgLMhUucmVsbG0uRX'
    'hwaXJhYmxlVG9rZW5SDHJlZnJlc2hUb2tlbhI4CgxhY2Nlc3NfdG9rZW4YAiABKAsyFS5yZWxs'
    'bS5FeHBpcmFibGVUb2tlblILYWNjZXNzVG9rZW4SHwoEdXNlchgDIAEoCzILLnJlbGxtLlVzZX'
    'JSBHVzZXISWAoWdmVyaWZpY2F0aW9uX2NoYWxsZW5nZRgEIAEoCzIcLnJlbGxtLlZlcmlmaWNh'
    'dGlvbkNoYWxsZW5nZUgAUhV2ZXJpZmljYXRpb25DaGFsbGVuZ2WIAQFCGQoXX3ZlcmlmaWNhdG'
    'lvbl9jaGFsbGVuZ2U=');

@$core.Deprecated('Use verificationChallengeDescriptor instead')
const VerificationChallenge$json = {
  '1': 'VerificationChallenge',
  '2': [
    {'1': 'sent_to', '3': 1, '4': 3, '5': 9, '10': 'sentTo'},
    {'1': 'expires_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'expiresAt'},
    {'1': 'resend_available_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'resendAvailableAt'},
  ],
};

/// Descriptor for `VerificationChallenge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verificationChallengeDescriptor = $convert.base64Decode(
    'ChVWZXJpZmljYXRpb25DaGFsbGVuZ2USFwoHc2VudF90bxgBIAMoCVIGc2VudFRvEjkKCmV4cG'
    'lyZXNfYXQYAiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUglleHBpcmVzQXQSSgoT'
    'cmVzZW5kX2F2YWlsYWJsZV9hdBgDIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSEX'
    'Jlc2VuZEF2YWlsYWJsZUF0');

@$core.Deprecated('Use expirableTokenDescriptor instead')
const ExpirableToken$json = {
  '1': 'ExpirableToken',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {'1': 'expires_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'expiresAt', '17': true},
  ],
  '8': [
    {'1': '_expires_at'},
  ],
};

/// Descriptor for `ExpirableToken`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List expirableTokenDescriptor = $convert.base64Decode(
    'Cg5FeHBpcmFibGVUb2tlbhIUCgV0b2tlbhgBIAEoCVIFdG9rZW4SPgoKZXhwaXJlc19hdBgCIA'
    'EoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAFIJZXhwaXJlc0F0iAEBQg0KC19leHBp'
    'cmVzX2F0');

@$core.Deprecated('Use accessTokenRequestDescriptor instead')
const AccessTokenRequest$json = {
  '1': 'AccessTokenRequest',
  '2': [
    {'1': 'refresh_token', '3': 1, '4': 1, '5': 9, '10': 'refreshToken'},
    {'1': 'expires_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'expiresAt', '17': true},
  ],
  '8': [
    {'1': '_expires_at'},
  ],
};

/// Descriptor for `AccessTokenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accessTokenRequestDescriptor = $convert.base64Decode(
    'ChJBY2Nlc3NUb2tlblJlcXVlc3QSIwoNcmVmcmVzaF90b2tlbhgBIAEoCVIMcmVmcmVzaFRva2'
    'VuEj4KCmV4cGlyZXNfYXQYAiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wSABSCWV4'
    'cGlyZXNBdIgBAUINCgtfZXhwaXJlc19hdA==');

@$core.Deprecated('Use accessTokenResponseDescriptor instead')
const AccessTokenResponse$json = {
  '1': 'AccessTokenResponse',
  '2': [
    {'1': 'refresh_token', '3': 1, '4': 1, '5': 11, '6': '.rellm.ExpirableToken', '9': 0, '10': 'refreshToken', '17': true},
    {'1': 'access_token', '3': 2, '4': 1, '5': 11, '6': '.rellm.ExpirableToken', '10': 'accessToken'},
  ],
  '8': [
    {'1': '_refresh_token'},
  ],
};

/// Descriptor for `AccessTokenResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accessTokenResponseDescriptor = $convert.base64Decode(
    'ChNBY2Nlc3NUb2tlblJlc3BvbnNlEj8KDXJlZnJlc2hfdG9rZW4YASABKAsyFS5yZWxsbS5FeH'
    'BpcmFibGVUb2tlbkgAUgxyZWZyZXNoVG9rZW6IAQESOAoMYWNjZXNzX3Rva2VuGAIgASgLMhUu'
    'cmVsbG0uRXhwaXJhYmxlVG9rZW5SC2FjY2Vzc1Rva2VuQhAKDl9yZWZyZXNoX3Rva2Vu');

@$core.Deprecated('Use resetPasswordRequestDescriptor instead')
const ResetPasswordRequest$json = {
  '1': 'ResetPasswordRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'userId', '17': true},
    {'1': 'password', '3': 3, '4': 1, '5': 9, '10': 'password'},
  ],
  '8': [
    {'1': '_user_id'},
  ],
};

/// Descriptor for `ResetPasswordRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetPasswordRequestDescriptor = $convert.base64Decode(
    'ChRSZXNldFBhc3N3b3JkUmVxdWVzdBIcCgd1c2VyX2lkGAEgASgJSABSBnVzZXJJZIgBARIaCg'
    'hwYXNzd29yZBgDIAEoCVIIcGFzc3dvcmRCCgoIX3VzZXJfaWQ=');

@$core.Deprecated('Use userRefreshTokensResponseDescriptor instead')
const UserRefreshTokensResponse$json = {
  '1': 'UserRefreshTokensResponse',
  '2': [
    {'1': 'refresh_tokens', '3': 1, '4': 3, '5': 11, '6': '.rellm.RefreshTokenMetadata', '10': 'refreshTokens'},
  ],
};

/// Descriptor for `UserRefreshTokensResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userRefreshTokensResponseDescriptor = $convert.base64Decode(
    'ChlVc2VyUmVmcmVzaFRva2Vuc1Jlc3BvbnNlEkIKDnJlZnJlc2hfdG9rZW5zGAEgAygLMhsucm'
    'VsbG0uUmVmcmVzaFRva2VuTWV0YWRhdGFSDXJlZnJlc2hUb2tlbnM=');

@$core.Deprecated('Use refreshTokenMetadataDescriptor instead')
const RefreshTokenMetadata$json = {
  '1': 'RefreshTokenMetadata',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'expires_at', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'expiresAt', '17': true},
    {'1': 'device_name', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'deviceName', '17': true},
    {'1': 'is_this_device', '3': 4, '4': 1, '5': 8, '10': 'isThisDevice'},
    {'1': 'third_party', '3': 5, '4': 1, '5': 8, '10': 'thirdParty'},
  ],
  '8': [
    {'1': '_expires_at'},
    {'1': '_device_name'},
  ],
};

/// Descriptor for `RefreshTokenMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List refreshTokenMetadataDescriptor = $convert.base64Decode(
    'ChRSZWZyZXNoVG9rZW5NZXRhZGF0YRIOCgJpZBgBIAEoBFICaWQSPgoKZXhwaXJlc19hdBgCIA'
    'EoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAFIJZXhwaXJlc0F0iAEBEiQKC2Rldmlj'
    'ZV9uYW1lGAMgASgJSAFSCmRldmljZU5hbWWIAQESJAoOaXNfdGhpc19kZXZpY2UYBCABKAhSDG'
    'lzVGhpc0RldmljZRIfCgt0aGlyZF9wYXJ0eRgFIAEoCFIKdGhpcmRQYXJ0eUINCgtfZXhwaXJl'
    'c19hdEIOCgxfZGV2aWNlX25hbWU=');

