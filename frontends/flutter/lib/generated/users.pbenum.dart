//
//  Generated code. Do not modify.
//  source: users.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Whether a user has consented to being contacted (e.g. via SMS/email sent by external services)
/// through a given [`ContactMethod`](#rellm-ContactMethod). See
/// [`ContactMethod.consent_state`](#rellm-ContactMethod).
class ContactConsentState extends $pb.ProtobufEnum {
  static const ContactConsentState CONTACT_CONSENT_REVOKED = ContactConsentState._(0, _omitEnumNames ? '' : 'CONTACT_CONSENT_REVOKED');
  static const ContactConsentState CONTACT_CONSENT_GRANTED = ContactConsentState._(1, _omitEnumNames ? '' : 'CONTACT_CONSENT_GRANTED');

  static const $core.List<ContactConsentState> values = <ContactConsentState> [
    CONTACT_CONSENT_REVOKED,
    CONTACT_CONSENT_GRANTED,
  ];

  static final $core.Map<$core.int, ContactConsentState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ContactConsentState? valueOf($core.int value) => _byValue[value];

  const ContactConsentState._($core.int v, $core.String n) : super(v, n);
}

/// Ways of listing users.
class UserListingType extends $pb.ProtobufEnum {
  static const UserListingType EVERYONE = UserListingType._(0, _omitEnumNames ? '' : 'EVERYONE');
  static const UserListingType FOLLOWING = UserListingType._(1, _omitEnumNames ? '' : 'FOLLOWING');
  static const UserListingType FRIENDS = UserListingType._(2, _omitEnumNames ? '' : 'FRIENDS');
  static const UserListingType FOLLOWERS = UserListingType._(3, _omitEnumNames ? '' : 'FOLLOWERS');
  static const UserListingType FOLLOW_REQUESTS = UserListingType._(4, _omitEnumNames ? '' : 'FOLLOW_REQUESTS');
  static const UserListingType USERS_TEXT_SEARCH = UserListingType._(5, _omitEnumNames ? '' : 'USERS_TEXT_SEARCH');
  static const UserListingType FOLLOWERS_TEXT_SEARCH = UserListingType._(6, _omitEnumNames ? '' : 'FOLLOWERS_TEXT_SEARCH');
  static const UserListingType FOLLOWING_TEXT_SEARCH = UserListingType._(7, _omitEnumNames ? '' : 'FOLLOWING_TEXT_SEARCH');
  static const UserListingType FRIENDS_TEXT_SEARCH = UserListingType._(8, _omitEnumNames ? '' : 'FRIENDS_TEXT_SEARCH');
  static const UserListingType FOLLOW_REQUESTS_TEXT_SEARCH = UserListingType._(9, _omitEnumNames ? '' : 'FOLLOW_REQUESTS_TEXT_SEARCH');
  static const UserListingType ADMINS = UserListingType._(10, _omitEnumNames ? '' : 'ADMINS');

  static const $core.List<UserListingType> values = <UserListingType> [
    EVERYONE,
    FOLLOWING,
    FRIENDS,
    FOLLOWERS,
    FOLLOW_REQUESTS,
    USERS_TEXT_SEARCH,
    FOLLOWERS_TEXT_SEARCH,
    FOLLOWING_TEXT_SEARCH,
    FRIENDS_TEXT_SEARCH,
    FOLLOW_REQUESTS_TEXT_SEARCH,
    ADMINS,
  ];

  static final $core.Map<$core.int, UserListingType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static UserListingType? valueOf($core.int value) => _byValue[value];

  const UserListingType._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
