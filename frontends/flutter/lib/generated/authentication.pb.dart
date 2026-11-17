//
//  Generated code. Do not modify.
//  source: authentication.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/timestamp.pb.dart' as $14;
import 'users.pb.dart' as $4;

///  Request to create a new account. Three ways to prove who you are, which may be combined:
///
///  - **Password** (`password` set): the classic flow. One request creates the account.
///  - **Verified SMS** (`phone` set, server has `CREATE_ACCOUNT_WITH_SMS` enabled) and/or
///  - **Verified email** (`email` set, server has `CREATE_ACCOUNT_WITH_EMAIL` enabled).
///
///  When a server has `CREATE_ACCOUNT_WITH_SMS`/`CREATE_ACCOUNT_WITH_EMAIL` enabled (see
///  [`AuthenticationFeature`](#rellm-AuthenticationFeature)), every `phone`/`email` supplied here
///  **must be verified before the account is created**, using two requests with the same contact
///  methods:
///
///  1. Send the request *without* the matching `phone_verification_code`/`email_verification_code`.
///     The contact method must have `consent_state` `CONTACT_CONSENT_GRANTED` (we're about to
///     message it). The server sends a code to each unverified contact method and returns a
///     [`RefreshTokenResponse`](#rellm-RefreshTokenResponse) with only `verification_challenge` set --
///     no account exists yet.
///  2. Repeat the request with the codes filled in. If every code is correct, the account is
///     created with those contact methods already verified (`verified_at` set), and tokens are
///     returned as usual.
///
///  If `password` is empty the account is passwordless: it can only be logged into via SMS/email
///  (see [`LoginRequest`](#rellm-LoginRequest)), so at least one of `phone`/`email` must be given.
///  A contact method that is already verified on another account is rejected
///  (`contact_already_verified`). If the server doesn't have the matching `CREATE_ACCOUNT_WITH_*`
///  feature enabled, `phone`/`email` are saved *unverified* exactly as before.
class CreateAccountRequest extends $pb.GeneratedMessage {
  factory CreateAccountRequest({
    $core.String? username,
    $core.String? password,
    $4.ContactMethod? email,
    $4.ContactMethod? phone,
    $14.Timestamp? expiresAt,
    $core.String? deviceName,
    $core.String? phoneVerificationCode,
    $core.String? emailVerificationCode,
  }) {
    final $result = create();
    if (username != null) {
      $result.username = username;
    }
    if (password != null) {
      $result.password = password;
    }
    if (email != null) {
      $result.email = email;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (phoneVerificationCode != null) {
      $result.phoneVerificationCode = phoneVerificationCode;
    }
    if (emailVerificationCode != null) {
      $result.emailVerificationCode = emailVerificationCode;
    }
    return $result;
  }
  CreateAccountRequest._() : super();
  factory CreateAccountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CreateAccountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CreateAccountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOM<$4.ContactMethod>(3, _omitFieldNames ? '' : 'email', subBuilder: $4.ContactMethod.create)
    ..aOM<$4.ContactMethod>(4, _omitFieldNames ? '' : 'phone', subBuilder: $4.ContactMethod.create)
    ..aOM<$14.Timestamp>(5, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(6, _omitFieldNames ? '' : 'deviceName')
    ..aOS(7, _omitFieldNames ? '' : 'phoneVerificationCode')
    ..aOS(8, _omitFieldNames ? '' : 'emailVerificationCode')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CreateAccountRequest clone() => CreateAccountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CreateAccountRequest copyWith(void Function(CreateAccountRequest) updates) => super.copyWith((message) => updates(message as CreateAccountRequest)) as CreateAccountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateAccountRequest create() => CreateAccountRequest._();
  CreateAccountRequest createEmptyInstance() => create();
  static $pb.PbList<CreateAccountRequest> createRepeated() => $pb.PbList<CreateAccountRequest>();
  @$core.pragma('dart2js:noInline')
  static CreateAccountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateAccountRequest>(create);
  static CreateAccountRequest? _defaultInstance;

  /// Username for the account to be created. Must not exist.
  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => clearField(1);

  /// Password for the account to be created. Must be at least 8 characters, or empty to create a
  /// passwordless (SMS/email-login-only) account -- see this message's own doc.
  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => clearField(2);

  /// Email to be used as a contact method.
  @$pb.TagNumber(3)
  $4.ContactMethod get email => $_getN(2);
  @$pb.TagNumber(3)
  set email($4.ContactMethod v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => clearField(3);
  @$pb.TagNumber(3)
  $4.ContactMethod ensureEmail() => $_ensure(2);

  /// Phone number to be used as a contact method.
  @$pb.TagNumber(4)
  $4.ContactMethod get phone => $_getN(3);
  @$pb.TagNumber(4)
  set phone($4.ContactMethod v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPhone() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhone() => clearField(4);
  @$pb.TagNumber(4)
  $4.ContactMethod ensurePhone() => $_ensure(3);

  /// Request an expiration time for the Auth Token returned. By default it will not expire.
  @$pb.TagNumber(5)
  $14.Timestamp get expiresAt => $_getN(4);
  @$pb.TagNumber(5)
  set expiresAt($14.Timestamp v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasExpiresAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearExpiresAt() => clearField(5);
  @$pb.TagNumber(5)
  $14.Timestamp ensureExpiresAt() => $_ensure(4);

  /// (Not yet implemented.) The name of the device being used to create the account.
  @$pb.TagNumber(6)
  $core.String get deviceName => $_getSZ(5);
  @$pb.TagNumber(6)
  set deviceName($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDeviceName() => $_has(5);
  @$pb.TagNumber(6)
  void clearDeviceName() => clearField(6);

  /// Second-phase code sent to `phone` (via SMS) by the first phase of this request. See this
  /// message's own doc.
  @$pb.TagNumber(7)
  $core.String get phoneVerificationCode => $_getSZ(6);
  @$pb.TagNumber(7)
  set phoneVerificationCode($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPhoneVerificationCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearPhoneVerificationCode() => clearField(7);

  /// Second-phase code sent to `email` by the first phase of this request. See this message's own
  /// doc.
  @$pb.TagNumber(8)
  $core.String get emailVerificationCode => $_getSZ(7);
  @$pb.TagNumber(8)
  set emailVerificationCode($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasEmailVerificationCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearEmailVerificationCode() => clearField(8);
}

enum LoginRequest_Request {
  usernamePassword, 
  sms, 
  email, 
  notSet
}

///  Request to login to an existing account. Exactly one of the `request` variants must be set.
///
///  `sms` and `email` logins are **two-phase**, and only work for a contact method that the account
///  has already *verified* (`ContactMethod.verified_at`, see
///  [`VerifyContactMethod`](#grpc-api-VerifyContactMethod)) and still consents to being contacted
///  through (`consent_state` `CONTACT_CONSENT_GRANTED`):
///
///  1. Send the request with no `code`. If an account matches, the server sends it a one-time code
///     and returns a [`RefreshTokenResponse`](#rellm-RefreshTokenResponse) with only
///     `verification_challenge` set. To avoid revealing which phone numbers/emails have accounts, the
///     response looks the same whether or not an account matched.
///  2. Send the request again with the `code`. On success the response carries tokens and the user,
///     as with a password login.
///
///  Codes are 6 digits, expire after 10 minutes, are limited to 5 wrong guesses, and can be re-sent
///  at most once a minute -- the same rules as [`ContactMethodVerification`](#rellm-ContactMethodVerification).
///  Servers advertise which login methods they allow in
///  [`ServerConfiguration.authentication_features`](#rellm-ServerConfiguration).
class LoginRequest extends $pb.GeneratedMessage {
  factory LoginRequest({
    UsernamePasswordLoginRequest? usernamePassword,
    SMSLoginRequest? sms,
    EmailLoginRequest? email,
  }) {
    final $result = create();
    if (usernamePassword != null) {
      $result.usernamePassword = usernamePassword;
    }
    if (sms != null) {
      $result.sms = sms;
    }
    if (email != null) {
      $result.email = email;
    }
    return $result;
  }
  LoginRequest._() : super();
  factory LoginRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoginRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, LoginRequest_Request> _LoginRequest_RequestByTag = {
    1 : LoginRequest_Request.usernamePassword,
    2 : LoginRequest_Request.sms,
    3 : LoginRequest_Request.email,
    0 : LoginRequest_Request.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoginRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOM<UsernamePasswordLoginRequest>(1, _omitFieldNames ? '' : 'usernamePassword', subBuilder: UsernamePasswordLoginRequest.create)
    ..aOM<SMSLoginRequest>(2, _omitFieldNames ? '' : 'sms', subBuilder: SMSLoginRequest.create)
    ..aOM<EmailLoginRequest>(3, _omitFieldNames ? '' : 'email', subBuilder: EmailLoginRequest.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoginRequest clone() => LoginRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoginRequest copyWith(void Function(LoginRequest) updates) => super.copyWith((message) => updates(message as LoginRequest)) as LoginRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoginRequest create() => LoginRequest._();
  LoginRequest createEmptyInstance() => create();
  static $pb.PbList<LoginRequest> createRepeated() => $pb.PbList<LoginRequest>();
  @$core.pragma('dart2js:noInline')
  static LoginRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoginRequest>(create);
  static LoginRequest? _defaultInstance;

  LoginRequest_Request whichRequest() => _LoginRequest_RequestByTag[$_whichOneof(0)]!;
  void clearRequest() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  UsernamePasswordLoginRequest get usernamePassword => $_getN(0);
  @$pb.TagNumber(1)
  set usernamePassword(UsernamePasswordLoginRequest v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasUsernamePassword() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsernamePassword() => clearField(1);
  @$pb.TagNumber(1)
  UsernamePasswordLoginRequest ensureUsernamePassword() => $_ensure(0);

  @$pb.TagNumber(2)
  SMSLoginRequest get sms => $_getN(1);
  @$pb.TagNumber(2)
  set sms(SMSLoginRequest v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSms() => $_has(1);
  @$pb.TagNumber(2)
  void clearSms() => clearField(2);
  @$pb.TagNumber(2)
  SMSLoginRequest ensureSms() => $_ensure(1);

  @$pb.TagNumber(3)
  EmailLoginRequest get email => $_getN(2);
  @$pb.TagNumber(3)
  set email(EmailLoginRequest v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => clearField(3);
  @$pb.TagNumber(3)
  EmailLoginRequest ensureEmail() => $_ensure(2);
}

/// Request to login with username + password.
class UsernamePasswordLoginRequest extends $pb.GeneratedMessage {
  factory UsernamePasswordLoginRequest({
    $core.String? username,
    $core.String? password,
    $14.Timestamp? expiresAt,
    $core.String? deviceName,
    $core.String? userId,
  }) {
    final $result = create();
    if (username != null) {
      $result.username = username;
    }
    if (password != null) {
      $result.password = password;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    return $result;
  }
  UsernamePasswordLoginRequest._() : super();
  factory UsernamePasswordLoginRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UsernamePasswordLoginRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UsernamePasswordLoginRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOM<$14.Timestamp>(3, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(4, _omitFieldNames ? '' : 'deviceName')
    ..aOS(5, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UsernamePasswordLoginRequest clone() => UsernamePasswordLoginRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UsernamePasswordLoginRequest copyWith(void Function(UsernamePasswordLoginRequest) updates) => super.copyWith((message) => updates(message as UsernamePasswordLoginRequest)) as UsernamePasswordLoginRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UsernamePasswordLoginRequest create() => UsernamePasswordLoginRequest._();
  UsernamePasswordLoginRequest createEmptyInstance() => create();
  static $pb.PbList<UsernamePasswordLoginRequest> createRepeated() => $pb.PbList<UsernamePasswordLoginRequest>();
  @$core.pragma('dart2js:noInline')
  static UsernamePasswordLoginRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UsernamePasswordLoginRequest>(create);
  static UsernamePasswordLoginRequest? _defaultInstance;

  /// Username for the account to be logged into. Must exist.
  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => clearField(1);

  /// Password for the account to be logged into.
  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => clearField(2);

  /// Request an expiration time for the Auth Token returned. By default it will not expire.
  @$pb.TagNumber(3)
  $14.Timestamp get expiresAt => $_getN(2);
  @$pb.TagNumber(3)
  set expiresAt($14.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasExpiresAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAt() => clearField(3);
  @$pb.TagNumber(3)
  $14.Timestamp ensureExpiresAt() => $_ensure(2);

  /// (Not yet implemented.) The name of the device being used to login.
  @$pb.TagNumber(4)
  $core.String get deviceName => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceName() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceName() => clearField(4);

  /// (TODO) If provided, username is ignored and login is initiated via user_id instead.
  @$pb.TagNumber(5)
  $core.String get userId => $_getSZ(4);
  @$pb.TagNumber(5)
  set userId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserId() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserId() => clearField(5);
}

/// Request to login via SMS. Two SMSLoginRequests are required to complete
/// a login.
class SMSLoginRequest extends $pb.GeneratedMessage {
  factory SMSLoginRequest({
    $core.String? phoneNumber,
    $core.String? code,
    $14.Timestamp? expiresAt,
    $core.String? deviceName,
    $core.String? userId,
    $core.bool? consentToContact,
  }) {
    final $result = create();
    if (phoneNumber != null) {
      $result.phoneNumber = phoneNumber;
    }
    if (code != null) {
      $result.code = code;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (consentToContact != null) {
      $result.consentToContact = consentToContact;
    }
    return $result;
  }
  SMSLoginRequest._() : super();
  factory SMSLoginRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SMSLoginRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SMSLoginRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'phoneNumber')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..aOM<$14.Timestamp>(3, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(4, _omitFieldNames ? '' : 'deviceName')
    ..aOS(5, _omitFieldNames ? '' : 'userId')
    ..aOB(6, _omitFieldNames ? '' : 'consentToContact')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SMSLoginRequest clone() => SMSLoginRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SMSLoginRequest copyWith(void Function(SMSLoginRequest) updates) => super.copyWith((message) => updates(message as SMSLoginRequest)) as SMSLoginRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SMSLoginRequest create() => SMSLoginRequest._();
  SMSLoginRequest createEmptyInstance() => create();
  static $pb.PbList<SMSLoginRequest> createRepeated() => $pb.PbList<SMSLoginRequest>();
  @$core.pragma('dart2js:noInline')
  static SMSLoginRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SMSLoginRequest>(create);
  static SMSLoginRequest? _defaultInstance;

  /// The phone number to be used for login, in E.164 format (`+19195551234`); a leading `tel:` is
  /// accepted. Always required. Must be a phone number the account has verified.
  @$pb.TagNumber(1)
  $core.String get phoneNumber => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneNumber($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPhoneNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneNumber() => clearField(1);

  /// Response code sent to the phone number via SMS for the second phase of authentication. Must be valid.
  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => clearField(2);

  /// Request an expiration time for the Auth Token returned. By default it will not expire.
  @$pb.TagNumber(3)
  $14.Timestamp get expiresAt => $_getN(2);
  @$pb.TagNumber(3)
  set expiresAt($14.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasExpiresAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAt() => clearField(3);
  @$pb.TagNumber(3)
  $14.Timestamp ensureExpiresAt() => $_ensure(2);

  /// (Not yet implemented.) The name of the device being used to login.
  @$pb.TagNumber(4)
  $core.String get deviceName => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceName() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceName() => clearField(4);

  /// Only needed if (unusually) more than one account has this contact method verified: picks
  /// which account to log into. Otherwise ignored.
  @$pb.TagNumber(5)
  $core.String get userId => $_getSZ(4);
  @$pb.TagNumber(5)
  set userId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserId() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserId() => clearField(5);

  /// The person signing in attests that they consent to being sent one-time sign-in codes by SMS
  /// (the sign-in form's consent checkbox). Send it on **both** phases. Only matters when the
  /// matched account's phone `ContactMethod.consent_state` is not `CONTACT_CONSENT_GRANTED` (they
  /// unchecked it, or replied STOP): with it set, phase 1 sends the code anyway, and phase 2 --
  /// once the code proves control of the phone number -- records the consent
  /// (`CONTACT_CONSENT_GRANTED`, with a server-timestamped `consent_history` entry). Without it, a
  /// contact method that doesn't consent is sent nothing (the response is unchanged, see
  /// [`LoginRequest`](#rellm-LoginRequest)). Never changes consent on its own: an unverified
  /// phase 2 changes nothing, so it can't be used to grant consent for a number you don't control.
  @$pb.TagNumber(6)
  $core.bool get consentToContact => $_getBF(5);
  @$pb.TagNumber(6)
  set consentToContact($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasConsentToContact() => $_has(5);
  @$pb.TagNumber(6)
  void clearConsentToContact() => clearField(6);
}

/// Request to login via email. Two EmailLoginRequests are required to complete
/// a login.
class EmailLoginRequest extends $pb.GeneratedMessage {
  factory EmailLoginRequest({
    $core.String? email,
    $core.String? code,
    $14.Timestamp? expiresAt,
    $core.String? deviceName,
    $core.String? userId,
    $core.bool? consentToContact,
  }) {
    final $result = create();
    if (email != null) {
      $result.email = email;
    }
    if (code != null) {
      $result.code = code;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (consentToContact != null) {
      $result.consentToContact = consentToContact;
    }
    return $result;
  }
  EmailLoginRequest._() : super();
  factory EmailLoginRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmailLoginRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EmailLoginRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..aOM<$14.Timestamp>(3, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(4, _omitFieldNames ? '' : 'deviceName')
    ..aOS(5, _omitFieldNames ? '' : 'userId')
    ..aOB(6, _omitFieldNames ? '' : 'consentToContact')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmailLoginRequest clone() => EmailLoginRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmailLoginRequest copyWith(void Function(EmailLoginRequest) updates) => super.copyWith((message) => updates(message as EmailLoginRequest)) as EmailLoginRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmailLoginRequest create() => EmailLoginRequest._();
  EmailLoginRequest createEmptyInstance() => create();
  static $pb.PbList<EmailLoginRequest> createRepeated() => $pb.PbList<EmailLoginRequest>();
  @$core.pragma('dart2js:noInline')
  static EmailLoginRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmailLoginRequest>(create);
  static EmailLoginRequest? _defaultInstance;

  /// The email address to be used for login (a leading `mailto:` is accepted; matched
  /// case-insensitively). Always required. Must be an address the account has verified.
  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => clearField(1);

  /// Response code sent to the email address for the second phase of authentication. Must be valid.
  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => clearField(2);

  /// Request an expiration time for the Auth Token returned. By default it will not expire.
  @$pb.TagNumber(3)
  $14.Timestamp get expiresAt => $_getN(2);
  @$pb.TagNumber(3)
  set expiresAt($14.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasExpiresAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAt() => clearField(3);
  @$pb.TagNumber(3)
  $14.Timestamp ensureExpiresAt() => $_ensure(2);

  /// (Not yet implemented.) The name of the device being used to login.
  @$pb.TagNumber(4)
  $core.String get deviceName => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceName() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceName() => clearField(4);

  /// Only needed if (unusually) more than one account has this contact method verified: picks
  /// which account to log into. Otherwise ignored.
  @$pb.TagNumber(5)
  $core.String get userId => $_getSZ(4);
  @$pb.TagNumber(5)
  set userId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserId() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserId() => clearField(5);

  /// Same as [`SMSLoginRequest.consent_to_contact`](#rellm-SMSLoginRequest), for the account's
  /// email `ContactMethod`.
  @$pb.TagNumber(6)
  $core.bool get consentToContact => $_getBF(5);
  @$pb.TagNumber(6)
  set consentToContact($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasConsentToContact() => $_has(5);
  @$pb.TagNumber(6)
  void clearConsentToContact() => clearField(6);
}

///  Request to create a new third-party refresh token. Unlike [`LoginRequest`](#rellm-LoginRequest) or [`CreateAccountRequest`](#rellm-CreateAccountRequest), the user must be logged in to create a third-party refresh token.
///
///  Generally, this is used to create a refresh token for another Rellm instance,
///  e.g., accessing `bullcity.social/jon`'s data from `jonline.io`. On the web side, this is implemented as follows:
///
///  1. When the `bullcity.social` user wants to login on `jonline.io`, `bullcity.social` will redirect
///  the user to `jonline.io/third_party_auth?to=bullcity.social`.
///  2. `jonline.io` will force the user to login if needed on this page.
///  3. `jonline.io` will prompt/warn the user, and then call this RPC to create a refresh + access token for `bullcity.social`.
///  4. `jonline.io` will redirect the user back to `bullcity.social/third_party_auth?from=jonline.io&token=<Base64RefreshTokenResponse>` with the refresh token POSTed in form data.
///      * (`<Base64RefreshTokenResponse>` is a base64-encoded [`RefreshTokenResponse`](#rellm-RefreshTokenResponse) message.)
///  6. `bullcity.social` will ensure it can [`GetCurrentUser`](#grpc-api-GetCurrentUser) on `jonline.io` with its new auth token.
///  5. `bullcity.social` will replace the current location with `bullcity.social/third_party_auth?from=jonline.io`.
///  7. `bullcity.social` will use the access token to make requests to `jonline.io` (the same as with `bullcity.social`).
///
///  Note that refresh tokens
class CreateThirdPartyRefreshTokenRequest extends $pb.GeneratedMessage {
  factory CreateThirdPartyRefreshTokenRequest({
    $14.Timestamp? expiresAt,
    $core.String? userId,
    $core.String? deviceName,
  }) {
    final $result = create();
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    return $result;
  }
  CreateThirdPartyRefreshTokenRequest._() : super();
  factory CreateThirdPartyRefreshTokenRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CreateThirdPartyRefreshTokenRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CreateThirdPartyRefreshTokenRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<$14.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..aOS(4, _omitFieldNames ? '' : 'deviceName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CreateThirdPartyRefreshTokenRequest clone() => CreateThirdPartyRefreshTokenRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CreateThirdPartyRefreshTokenRequest copyWith(void Function(CreateThirdPartyRefreshTokenRequest) updates) => super.copyWith((message) => updates(message as CreateThirdPartyRefreshTokenRequest)) as CreateThirdPartyRefreshTokenRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateThirdPartyRefreshTokenRequest create() => CreateThirdPartyRefreshTokenRequest._();
  CreateThirdPartyRefreshTokenRequest createEmptyInstance() => create();
  static $pb.PbList<CreateThirdPartyRefreshTokenRequest> createRepeated() => $pb.PbList<CreateThirdPartyRefreshTokenRequest>();
  @$core.pragma('dart2js:noInline')
  static CreateThirdPartyRefreshTokenRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateThirdPartyRefreshTokenRequest>(create);
  static CreateThirdPartyRefreshTokenRequest? _defaultInstance;

  /// The third-party refresh token's expiration time.
  @$pb.TagNumber(2)
  $14.Timestamp get expiresAt => $_getN(0);
  @$pb.TagNumber(2)
  set expiresAt($14.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(0);
  @$pb.TagNumber(2)
  void clearExpiresAt() => clearField(2);
  @$pb.TagNumber(2)
  $14.Timestamp ensureExpiresAt() => $_ensure(0);

  /// The third-party refresh token's user ID.
  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(3)
  void clearUserId() => clearField(3);

  /// The third-party refresh token's device name.
  @$pb.TagNumber(4)
  $core.String get deviceName => $_getSZ(2);
  @$pb.TagNumber(4)
  set deviceName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceName() => $_has(2);
  @$pb.TagNumber(4)
  void clearDeviceName() => clearField(4);
}

/// Returned when creating an account, logging in, or creating a third-party refresh token.
class RefreshTokenResponse extends $pb.GeneratedMessage {
  factory RefreshTokenResponse({
    ExpirableToken? refreshToken,
    ExpirableToken? accessToken,
    $4.User? user,
    VerificationChallenge? verificationChallenge,
  }) {
    final $result = create();
    if (refreshToken != null) {
      $result.refreshToken = refreshToken;
    }
    if (accessToken != null) {
      $result.accessToken = accessToken;
    }
    if (user != null) {
      $result.user = user;
    }
    if (verificationChallenge != null) {
      $result.verificationChallenge = verificationChallenge;
    }
    return $result;
  }
  RefreshTokenResponse._() : super();
  factory RefreshTokenResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RefreshTokenResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RefreshTokenResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<ExpirableToken>(1, _omitFieldNames ? '' : 'refreshToken', subBuilder: ExpirableToken.create)
    ..aOM<ExpirableToken>(2, _omitFieldNames ? '' : 'accessToken', subBuilder: ExpirableToken.create)
    ..aOM<$4.User>(3, _omitFieldNames ? '' : 'user', subBuilder: $4.User.create)
    ..aOM<VerificationChallenge>(4, _omitFieldNames ? '' : 'verificationChallenge', subBuilder: VerificationChallenge.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RefreshTokenResponse clone() => RefreshTokenResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RefreshTokenResponse copyWith(void Function(RefreshTokenResponse) updates) => super.copyWith((message) => updates(message as RefreshTokenResponse)) as RefreshTokenResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RefreshTokenResponse create() => RefreshTokenResponse._();
  RefreshTokenResponse createEmptyInstance() => create();
  static $pb.PbList<RefreshTokenResponse> createRepeated() => $pb.PbList<RefreshTokenResponse>();
  @$core.pragma('dart2js:noInline')
  static RefreshTokenResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RefreshTokenResponse>(create);
  static RefreshTokenResponse? _defaultInstance;

  /// The persisted token the device should store and associate with the account.
  /// Used to request new access tokens.
  @$pb.TagNumber(1)
  ExpirableToken get refreshToken => $_getN(0);
  @$pb.TagNumber(1)
  set refreshToken(ExpirableToken v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRefreshToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearRefreshToken() => clearField(1);
  @$pb.TagNumber(1)
  ExpirableToken ensureRefreshToken() => $_ensure(0);

  /// An initial access token provided for convenience.
  @$pb.TagNumber(2)
  ExpirableToken get accessToken => $_getN(1);
  @$pb.TagNumber(2)
  set accessToken(ExpirableToken v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccessToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccessToken() => clearField(2);
  @$pb.TagNumber(2)
  ExpirableToken ensureAccessToken() => $_ensure(1);

  /// The user associated with the account that was created/logged into.
  @$pb.TagNumber(3)
  $4.User get user => $_getN(2);
  @$pb.TagNumber(3)
  set user($4.User v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasUser() => $_has(2);
  @$pb.TagNumber(3)
  void clearUser() => clearField(3);
  @$pb.TagNumber(3)
  $4.User ensureUser() => $_ensure(2);

  /// Set *instead of* the tokens and `user` when this was the first phase of a two-phase
  /// [`LoginRequest`](#rellm-LoginRequest) (SMS/email) or [`CreateAccountRequest`](#rellm-CreateAccountRequest):
  /// a code was sent (or, for login, would have been -- see `LoginRequest`), and the client should
  /// prompt for it and repeat the request with the code filled in.
  @$pb.TagNumber(4)
  VerificationChallenge get verificationChallenge => $_getN(3);
  @$pb.TagNumber(4)
  set verificationChallenge(VerificationChallenge v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVerificationChallenge() => $_has(3);
  @$pb.TagNumber(4)
  void clearVerificationChallenge() => clearField(4);
  @$pb.TagNumber(4)
  VerificationChallenge ensureVerificationChallenge() => $_ensure(3);
}

/// Returned in [`RefreshTokenResponse.verification_challenge`](#rellm-RefreshTokenResponse) after the
/// first phase of an SMS/email login or account creation.
class VerificationChallenge extends $pb.GeneratedMessage {
  factory VerificationChallenge({
    $core.Iterable<$core.String>? sentTo,
    $14.Timestamp? expiresAt,
    $14.Timestamp? resendAvailableAt,
  }) {
    final $result = create();
    if (sentTo != null) {
      $result.sentTo.addAll(sentTo);
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (resendAvailableAt != null) {
      $result.resendAvailableAt = resendAvailableAt;
    }
    return $result;
  }
  VerificationChallenge._() : super();
  factory VerificationChallenge.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VerificationChallenge.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VerificationChallenge', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'sentTo')
    ..aOM<$14.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOM<$14.Timestamp>(3, _omitFieldNames ? '' : 'resendAvailableAt', subBuilder: $14.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VerificationChallenge clone() => VerificationChallenge()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VerificationChallenge copyWith(void Function(VerificationChallenge) updates) => super.copyWith((message) => updates(message as VerificationChallenge)) as VerificationChallenge;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VerificationChallenge create() => VerificationChallenge._();
  VerificationChallenge createEmptyInstance() => create();
  static $pb.PbList<VerificationChallenge> createRepeated() => $pb.PbList<VerificationChallenge>();
  @$core.pragma('dart2js:noInline')
  static VerificationChallenge getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VerificationChallenge>(create);
  static VerificationChallenge? _defaultInstance;

  /// The `tel:`/`mailto:` values a code was sent to, e.g. `["tel:+19195551234"]` -- shown to the
  /// user as "We sent a code to ...". For login this echoes the requested value even when no
  /// account matched.
  @$pb.TagNumber(1)
  $core.List<$core.String> get sentTo => $_getList(0);

  /// When the code(s) expire (10 minutes after being sent).
  @$pb.TagNumber(2)
  $14.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($14.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => clearField(2);
  @$pb.TagNumber(2)
  $14.Timestamp ensureExpiresAt() => $_ensure(1);

  /// The earliest a new code can be requested for the same contact method.
  @$pb.TagNumber(3)
  $14.Timestamp get resendAvailableAt => $_getN(2);
  @$pb.TagNumber(3)
  set resendAvailableAt($14.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasResendAvailableAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearResendAvailableAt() => clearField(3);
  @$pb.TagNumber(3)
  $14.Timestamp ensureResendAvailableAt() => $_ensure(2);
}

/// Generic type for refresh and access tokens.
class ExpirableToken extends $pb.GeneratedMessage {
  factory ExpirableToken({
    $core.String? token,
    $14.Timestamp? expiresAt,
  }) {
    final $result = create();
    if (token != null) {
      $result.token = token;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    return $result;
  }
  ExpirableToken._() : super();
  factory ExpirableToken.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExpirableToken.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExpirableToken', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..aOM<$14.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExpirableToken clone() => ExpirableToken()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExpirableToken copyWith(void Function(ExpirableToken) updates) => super.copyWith((message) => updates(message as ExpirableToken)) as ExpirableToken;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExpirableToken create() => ExpirableToken._();
  ExpirableToken createEmptyInstance() => create();
  static $pb.PbList<ExpirableToken> createRepeated() => $pb.PbList<ExpirableToken>();
  @$core.pragma('dart2js:noInline')
  static ExpirableToken getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExpirableToken>(create);
  static ExpirableToken? _defaultInstance;

  /// The secure token value.
  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => clearField(1);

  /// Optional expiration time for the token. If not set, the token will not expire.
  @$pb.TagNumber(2)
  $14.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($14.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => clearField(2);
  @$pb.TagNumber(2)
  $14.Timestamp ensureExpiresAt() => $_ensure(1);
}

/// Request for a new access token using a refresh token.
class AccessTokenRequest extends $pb.GeneratedMessage {
  factory AccessTokenRequest({
    $core.String? refreshToken,
    $14.Timestamp? expiresAt,
  }) {
    final $result = create();
    if (refreshToken != null) {
      $result.refreshToken = refreshToken;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    return $result;
  }
  AccessTokenRequest._() : super();
  factory AccessTokenRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AccessTokenRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AccessTokenRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'refreshToken')
    ..aOM<$14.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AccessTokenRequest clone() => AccessTokenRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AccessTokenRequest copyWith(void Function(AccessTokenRequest) updates) => super.copyWith((message) => updates(message as AccessTokenRequest)) as AccessTokenRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AccessTokenRequest create() => AccessTokenRequest._();
  AccessTokenRequest createEmptyInstance() => create();
  static $pb.PbList<AccessTokenRequest> createRepeated() => $pb.PbList<AccessTokenRequest>();
  @$core.pragma('dart2js:noInline')
  static AccessTokenRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AccessTokenRequest>(create);
  static AccessTokenRequest? _defaultInstance;

  /// The refresh token to use to request a new access token.
  @$pb.TagNumber(1)
  $core.String get refreshToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set refreshToken($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRefreshToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearRefreshToken() => clearField(1);

  /// Optional *requested* expiration time for the token. Server may ignore this.
  @$pb.TagNumber(2)
  $14.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($14.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => clearField(2);
  @$pb.TagNumber(2)
  $14.Timestamp ensureExpiresAt() => $_ensure(1);
}

/// Returned when requesting access tokens.
class AccessTokenResponse extends $pb.GeneratedMessage {
  factory AccessTokenResponse({
    ExpirableToken? refreshToken,
    ExpirableToken? accessToken,
  }) {
    final $result = create();
    if (refreshToken != null) {
      $result.refreshToken = refreshToken;
    }
    if (accessToken != null) {
      $result.accessToken = accessToken;
    }
    return $result;
  }
  AccessTokenResponse._() : super();
  factory AccessTokenResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AccessTokenResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AccessTokenResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<ExpirableToken>(1, _omitFieldNames ? '' : 'refreshToken', subBuilder: ExpirableToken.create)
    ..aOM<ExpirableToken>(2, _omitFieldNames ? '' : 'accessToken', subBuilder: ExpirableToken.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AccessTokenResponse clone() => AccessTokenResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AccessTokenResponse copyWith(void Function(AccessTokenResponse) updates) => super.copyWith((message) => updates(message as AccessTokenResponse)) as AccessTokenResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AccessTokenResponse create() => AccessTokenResponse._();
  AccessTokenResponse createEmptyInstance() => create();
  static $pb.PbList<AccessTokenResponse> createRepeated() => $pb.PbList<AccessTokenResponse>();
  @$core.pragma('dart2js:noInline')
  static AccessTokenResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AccessTokenResponse>(create);
  static AccessTokenResponse? _defaultInstance;

  /// If a refresh token is returned, it should be stored. Old refresh tokens may expire *before*
  /// their indicated expiration.
  /// See: https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation
  @$pb.TagNumber(1)
  ExpirableToken get refreshToken => $_getN(0);
  @$pb.TagNumber(1)
  set refreshToken(ExpirableToken v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasRefreshToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearRefreshToken() => clearField(1);
  @$pb.TagNumber(1)
  ExpirableToken ensureRefreshToken() => $_ensure(0);

  /// The new access token.
  @$pb.TagNumber(2)
  ExpirableToken get accessToken => $_getN(1);
  @$pb.TagNumber(2)
  set accessToken(ExpirableToken v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccessToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccessToken() => clearField(2);
  @$pb.TagNumber(2)
  ExpirableToken ensureAccessToken() => $_ensure(1);
}

/// Request to reset a password.
class ResetPasswordRequest extends $pb.GeneratedMessage {
  factory ResetPasswordRequest({
    $core.String? userId,
    $core.String? password,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (password != null) {
      $result.password = password;
    }
    return $result;
  }
  ResetPasswordRequest._() : super();
  factory ResetPasswordRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ResetPasswordRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ResetPasswordRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ResetPasswordRequest clone() => ResetPasswordRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ResetPasswordRequest copyWith(void Function(ResetPasswordRequest) updates) => super.copyWith((message) => updates(message as ResetPasswordRequest)) as ResetPasswordRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResetPasswordRequest create() => ResetPasswordRequest._();
  ResetPasswordRequest createEmptyInstance() => create();
  static $pb.PbList<ResetPasswordRequest> createRepeated() => $pb.PbList<ResetPasswordRequest>();
  @$core.pragma('dart2js:noInline')
  static ResetPasswordRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResetPasswordRequest>(create);
  static ResetPasswordRequest? _defaultInstance;

  /// If not set, use the current user of the request.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The new password to set.
  @$pb.TagNumber(3)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(3)
  set password($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(3)
  void clearPassword() => clearField(3);
}

/// Response for `GetUserRefreshTokens` RPC. Returns all refresh tokens associated with the current user.
class UserRefreshTokensResponse extends $pb.GeneratedMessage {
  factory UserRefreshTokensResponse({
    $core.Iterable<RefreshTokenMetadata>? refreshTokens,
  }) {
    final $result = create();
    if (refreshTokens != null) {
      $result.refreshTokens.addAll(refreshTokens);
    }
    return $result;
  }
  UserRefreshTokensResponse._() : super();
  factory UserRefreshTokensResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UserRefreshTokensResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UserRefreshTokensResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<RefreshTokenMetadata>(1, _omitFieldNames ? '' : 'refreshTokens', $pb.PbFieldType.PM, subBuilder: RefreshTokenMetadata.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UserRefreshTokensResponse clone() => UserRefreshTokensResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UserRefreshTokensResponse copyWith(void Function(UserRefreshTokensResponse) updates) => super.copyWith((message) => updates(message as UserRefreshTokensResponse)) as UserRefreshTokensResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UserRefreshTokensResponse create() => UserRefreshTokensResponse._();
  UserRefreshTokensResponse createEmptyInstance() => create();
  static $pb.PbList<UserRefreshTokensResponse> createRepeated() => $pb.PbList<UserRefreshTokensResponse>();
  @$core.pragma('dart2js:noInline')
  static UserRefreshTokensResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserRefreshTokensResponse>(create);
  static UserRefreshTokensResponse? _defaultInstance;

  /// The refresh tokens associated with the current user.
  @$pb.TagNumber(1)
  $core.List<RefreshTokenMetadata> get refreshTokens => $_getList(0);
}

/// Metadata on a refresh token for the current user, used when managing refresh tokens as a user.
/// Does not include the token itself.
class RefreshTokenMetadata extends $pb.GeneratedMessage {
  factory RefreshTokenMetadata({
    $fixnum.Int64? id,
    $14.Timestamp? expiresAt,
    $core.String? deviceName,
    $core.bool? isThisDevice,
    $core.bool? thirdParty,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (expiresAt != null) {
      $result.expiresAt = expiresAt;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (isThisDevice != null) {
      $result.isThisDevice = isThisDevice;
    }
    if (thirdParty != null) {
      $result.thirdParty = thirdParty;
    }
    return $result;
  }
  RefreshTokenMetadata._() : super();
  factory RefreshTokenMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RefreshTokenMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RefreshTokenMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$14.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt', subBuilder: $14.Timestamp.create)
    ..aOS(3, _omitFieldNames ? '' : 'deviceName')
    ..aOB(4, _omitFieldNames ? '' : 'isThisDevice')
    ..aOB(5, _omitFieldNames ? '' : 'thirdParty')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RefreshTokenMetadata clone() => RefreshTokenMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RefreshTokenMetadata copyWith(void Function(RefreshTokenMetadata) updates) => super.copyWith((message) => updates(message as RefreshTokenMetadata)) as RefreshTokenMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RefreshTokenMetadata create() => RefreshTokenMetadata._();
  RefreshTokenMetadata createEmptyInstance() => create();
  static $pb.PbList<RefreshTokenMetadata> createRepeated() => $pb.PbList<RefreshTokenMetadata>();
  @$core.pragma('dart2js:noInline')
  static RefreshTokenMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RefreshTokenMetadata>(create);
  static RefreshTokenMetadata? _defaultInstance;

  /// The DB ID of the refresh token. Used when deleting the token or updating the device_name.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Expiration date of the refresh token.
  @$pb.TagNumber(2)
  $14.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($14.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => clearField(2);
  @$pb.TagNumber(2)
  $14.Timestamp ensureExpiresAt() => $_ensure(1);

  /// The device name the refresh token is on. User-updateable.
  @$pb.TagNumber(3)
  $core.String get deviceName => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeviceName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceName() => clearField(3);

  /// Whether the refresh token is associated with the current device
  /// (based on what user is making the request).
  @$pb.TagNumber(4)
  $core.bool get isThisDevice => $_getBF(3);
  @$pb.TagNumber(4)
  set isThisDevice($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsThisDevice() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsThisDevice() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get thirdParty => $_getBF(4);
  @$pb.TagNumber(5)
  set thirdParty($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThirdParty() => $_has(4);
  @$pb.TagNumber(5)
  void clearThirdParty() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
