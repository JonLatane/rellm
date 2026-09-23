//
//  Generated code. Do not modify.
//  source: server_configuration.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// A resource `ClusterResources.conductor_host` can hand out an exclusive, cluster-wide lock on
/// via [`LockClusterResources`](#grpc-api-LockClusterResources)/
/// [`FreeClusterResources`](#grpc-api-FreeClusterResources).
class ClusterResource extends $pb.ProtobufEnum {
  static const ClusterResource CLUSTER_RESOURCE_BROWSER = ClusterResource._(0, _omitEnumNames ? '' : 'CLUSTER_RESOURCE_BROWSER');
  static const ClusterResource CLUSTER_RESOURCE_FFMPEG = ClusterResource._(1, _omitEnumNames ? '' : 'CLUSTER_RESOURCE_FFMPEG');
  static const ClusterResource CLUSTER_RESOURCE_IMAGEMAGICK = ClusterResource._(2, _omitEnumNames ? '' : 'CLUSTER_RESOURCE_IMAGEMAGICK');

  static const $core.List<ClusterResource> values = <ClusterResource> [
    CLUSTER_RESOURCE_BROWSER,
    CLUSTER_RESOURCE_FFMPEG,
    CLUSTER_RESOURCE_IMAGEMAGICK,
  ];

  static final $core.Map<$core.int, ClusterResource> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ClusterResource? valueOf($core.int value) => _byValue[value];

  const ClusterResource._($core.int v, $core.String n) : super(v, n);
}

/// Authentication features that can be enabled/disabled by the server admin.
class AuthenticationFeature extends $pb.ProtobufEnum {
  static const AuthenticationFeature AUTHENTICATION_FEATURE_UNKNOWN = AuthenticationFeature._(0, _omitEnumNames ? '' : 'AUTHENTICATION_FEATURE_UNKNOWN');
  static const AuthenticationFeature CREATE_ACCOUNT = AuthenticationFeature._(1, _omitEnumNames ? '' : 'CREATE_ACCOUNT');
  static const AuthenticationFeature LOGIN = AuthenticationFeature._(2, _omitEnumNames ? '' : 'LOGIN');

  static const $core.List<AuthenticationFeature> values = <AuthenticationFeature> [
    AUTHENTICATION_FEATURE_UNKNOWN,
    CREATE_ACCOUNT,
    LOGIN,
  ];

  static final $core.Map<$core.int, AuthenticationFeature> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AuthenticationFeature? valueOf($core.int value) => _byValue[value];

  const AuthenticationFeature._($core.int v, $core.String n) : super(v, n);
}

/// The Events Calendar's default UI granularity.
class CalendarDisplayMode extends $pb.ProtobufEnum {
  static const CalendarDisplayMode CALENDAR_DISPLAY_WEEK = CalendarDisplayMode._(0, _omitEnumNames ? '' : 'CALENDAR_DISPLAY_WEEK');
  static const CalendarDisplayMode CALENDAR_DISPLAY_MONTH = CalendarDisplayMode._(1, _omitEnumNames ? '' : 'CALENDAR_DISPLAY_MONTH');
  static const CalendarDisplayMode CALENDAR_DISPLAY_DAY = CalendarDisplayMode._(3, _omitEnumNames ? '' : 'CALENDAR_DISPLAY_DAY');

  static const $core.List<CalendarDisplayMode> values = <CalendarDisplayMode> [
    CALENDAR_DISPLAY_WEEK,
    CALENDAR_DISPLAY_MONTH,
    CALENDAR_DISPLAY_DAY,
  ];

  static final $core.Map<$core.int, CalendarDisplayMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CalendarDisplayMode? valueOf($core.int value) => _byValue[value];

  const CalendarDisplayMode._($core.int v, $core.String n) : super(v, n);
}

/// Strategy when a user sets their visibility to `PRIVATE`.
class PrivateUserStrategy extends $pb.ProtobufEnum {
  static const PrivateUserStrategy ACCOUNT_IS_FROZEN = PrivateUserStrategy._(0, _omitEnumNames ? '' : 'ACCOUNT_IS_FROZEN');
  static const PrivateUserStrategy LIMITED_CREEPINESS = PrivateUserStrategy._(1, _omitEnumNames ? '' : 'LIMITED_CREEPINESS');
  static const PrivateUserStrategy LET_ME_CREEP_ON_PPL = PrivateUserStrategy._(2, _omitEnumNames ? '' : 'LET_ME_CREEP_ON_PPL');

  static const $core.List<PrivateUserStrategy> values = <PrivateUserStrategy> [
    ACCOUNT_IS_FROZEN,
    LIMITED_CREEPINESS,
    LET_ME_CREEP_ON_PPL,
  ];

  static final $core.Map<$core.int, PrivateUserStrategy> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PrivateUserStrategy? valueOf($core.int value) => _byValue[value];

  const PrivateUserStrategy._($core.int v, $core.String n) : super(v, n);
}

/// Offers a choice of web UIs. Generally though, React/Tamagui is
/// a century ahead of Flutter Web, so it's the default.
class WebUserInterface extends $pb.ProtobufEnum {
  static const WebUserInterface FLUTTER_WEB = WebUserInterface._(0, _omitEnumNames ? '' : 'FLUTTER_WEB');
  static const WebUserInterface HANDLEBARS_TEMPLATES = WebUserInterface._(1, _omitEnumNames ? '' : 'HANDLEBARS_TEMPLATES');
  static const WebUserInterface REACT_TAMAGUI = WebUserInterface._(2, _omitEnumNames ? '' : 'REACT_TAMAGUI');
  static const WebUserInterface ELM_SPA = WebUserInterface._(3, _omitEnumNames ? '' : 'ELM_SPA');

  static const $core.List<WebUserInterface> values = <WebUserInterface> [
    FLUTTER_WEB,
    HANDLEBARS_TEMPLATES,
    REACT_TAMAGUI,
    ELM_SPA,
  ];

  static final $core.Map<$core.int, WebUserInterface> _byValue = $pb.ProtobufEnum.initByValue(values);
  static WebUserInterface? valueOf($core.int value) => _byValue[value];

  const WebUserInterface._($core.int v, $core.String n) : super(v, n);
}

/// How a nav tab's icon and title are shown together, if at all. Applies uniformly to every tab
/// (`tabs` above, or the predefined `EVENTS_TAB`/`POSTS_TAB`/`PEOPLE_TAB`/`ABOUT_TAB` set when `tabs`
/// itself is unset) - there's no per-tab override.
class NavigationTabStyle extends $pb.ProtobufEnum {
  static const NavigationTabStyle NAVIGATION_TAB_ICON_ONLY = NavigationTabStyle._(0, _omitEnumNames ? '' : 'NAVIGATION_TAB_ICON_ONLY');
  static const NavigationTabStyle NAVIGATION_TAB_TEXT_ONLY = NavigationTabStyle._(1, _omitEnumNames ? '' : 'NAVIGATION_TAB_TEXT_ONLY');
  static const NavigationTabStyle NAVIGATION_TAB_ICON_AND_TEXT_BELOW = NavigationTabStyle._(2, _omitEnumNames ? '' : 'NAVIGATION_TAB_ICON_AND_TEXT_BELOW');
  static const NavigationTabStyle NAVIGATION_TAB_ICON_AND_TEXT_RIGHT = NavigationTabStyle._(3, _omitEnumNames ? '' : 'NAVIGATION_TAB_ICON_AND_TEXT_RIGHT');

  static const $core.List<NavigationTabStyle> values = <NavigationTabStyle> [
    NAVIGATION_TAB_ICON_ONLY,
    NAVIGATION_TAB_TEXT_ONLY,
    NAVIGATION_TAB_ICON_AND_TEXT_BELOW,
    NAVIGATION_TAB_ICON_AND_TEXT_RIGHT,
  ];

  static final $core.Map<$core.int, NavigationTabStyle> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NavigationTabStyle? valueOf($core.int value) => _byValue[value];

  const NavigationTabStyle._($core.int v, $core.String n) : super(v, n);
}

/// The default navigation tabs in Rellm's Elm UI.
class NavigationTab extends $pb.ProtobufEnum {
  static const NavigationTab HOME_TAB = NavigationTab._(0, _omitEnumNames ? '' : 'HOME_TAB');
  static const NavigationTab EVENTS_TAB = NavigationTab._(10, _omitEnumNames ? '' : 'EVENTS_TAB');
  static const NavigationTab POSTS_TAB = NavigationTab._(11, _omitEnumNames ? '' : 'POSTS_TAB');
  static const NavigationTab PEOPLE_TAB = NavigationTab._(12, _omitEnumNames ? '' : 'PEOPLE_TAB');
  static const NavigationTab ABOUT_TAB = NavigationTab._(15, _omitEnumNames ? '' : 'ABOUT_TAB');
  static const NavigationTab MARKET_TAB = NavigationTab._(16, _omitEnumNames ? '' : 'MARKET_TAB');

  static const $core.List<NavigationTab> values = <NavigationTab> [
    HOME_TAB,
    EVENTS_TAB,
    POSTS_TAB,
    PEOPLE_TAB,
    ABOUT_TAB,
    MARKET_TAB,
  ];

  static final $core.Map<$core.int, NavigationTab> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NavigationTab? valueOf($core.int value) => _byValue[value];

  const NavigationTab._($core.int v, $core.String n) : super(v, n);
}

/// The two contact schemes [`ContactMethod.value`](#rellm-ContactMethod) (`users.proto`) may take --
/// see [`ServerConfiguration.supported_contact_protocols`](#rellm-ServerConfiguration) for the
/// server-wide setting keyed off this enum, and `docs/contact_integrations.md` for the full picture.
class ContactProtocol extends $pb.ProtobufEnum {
  static const ContactProtocol CONTACT_PROTOCOL_TEL = ContactProtocol._(0, _omitEnumNames ? '' : 'CONTACT_PROTOCOL_TEL');
  static const ContactProtocol CONTACT_PROTOCOL_MAILTO = ContactProtocol._(1, _omitEnumNames ? '' : 'CONTACT_PROTOCOL_MAILTO');

  static const $core.List<ContactProtocol> values = <ContactProtocol> [
    CONTACT_PROTOCOL_TEL,
    CONTACT_PROTOCOL_MAILTO,
  ];

  static final $core.Map<$core.int, ContactProtocol> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ContactProtocol? valueOf($core.int value) => _byValue[value];

  const ContactProtocol._($core.int v, $core.String n) : super(v, n);
}

/// The SMS providers [`ServerConfiguration.preferred_verification_apis`](#rellm-ServerConfiguration)/
/// [`available_verification_apis`](#rellm-ServerConfiguration) order between --
/// [`TwilioConfig`](#rellm-TwilioConfig), [`BirdConfig`](#rellm-BirdConfig), and
/// [`TelnyxConfig`](#rellm-TelnyxConfig). See `contact_verification.rs`'s own module doc for the
/// preference-then-fallback logic these values drive.
class ContactVerificationAPI extends $pb.ProtobufEnum {
  static const ContactVerificationAPI CONTACT_VERIFICATION_API_TWILIO = ContactVerificationAPI._(0, _omitEnumNames ? '' : 'CONTACT_VERIFICATION_API_TWILIO');
  static const ContactVerificationAPI CONTACT_VERIFICATION_API_BIRD = ContactVerificationAPI._(1, _omitEnumNames ? '' : 'CONTACT_VERIFICATION_API_BIRD');
  static const ContactVerificationAPI CONTACT_VERIFICATION_API_TELNYX = ContactVerificationAPI._(2, _omitEnumNames ? '' : 'CONTACT_VERIFICATION_API_TELNYX');

  static const $core.List<ContactVerificationAPI> values = <ContactVerificationAPI> [
    CONTACT_VERIFICATION_API_TWILIO,
    CONTACT_VERIFICATION_API_BIRD,
    CONTACT_VERIFICATION_API_TELNYX,
  ];

  static final $core.Map<$core.int, ContactVerificationAPI> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ContactVerificationAPI? valueOf($core.int value) => _byValue[value];

  const ContactVerificationAPI._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
