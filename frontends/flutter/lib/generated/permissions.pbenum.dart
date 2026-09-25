//
//  Generated code. Do not modify.
//  source: permissions.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

///  Rellm Permissions are a set of permissions that can be granted directly to [`User`](#rellm-User)s and [`Membership`](#rellm-Membership)s.
///  (A [`Membership`](#rellm-Membership) is the link between a [`Group`](#rellm-Group) and a [`User`](#rellm-User).)
///
///  Subsets of these permissions are also applicable to anonymous users via [`anonymous_user_permissions` in `ServerConfiguration`](#rellm-ServerConfiguration),
///  and to Group non-members via [`non_member_permissions` in `Group`](#rellm-Group), as well as others documented there.
class Permission extends $pb.ProtobufEnum {
  static const Permission PERMISSION_UNKNOWN = Permission._(0, _omitEnumNames ? '' : 'PERMISSION_UNKNOWN');
  static const Permission VIEW_USERS = Permission._(1, _omitEnumNames ? '' : 'VIEW_USERS');
  static const Permission PUBLISH_USERS_LOCALLY = Permission._(2, _omitEnumNames ? '' : 'PUBLISH_USERS_LOCALLY');
  static const Permission PUBLISH_USERS_GLOBALLY = Permission._(3, _omitEnumNames ? '' : 'PUBLISH_USERS_GLOBALLY');
  static const Permission MODERATE_USERS = Permission._(4, _omitEnumNames ? '' : 'MODERATE_USERS');
  static const Permission FOLLOW_USERS = Permission._(5, _omitEnumNames ? '' : 'FOLLOW_USERS');
  static const Permission GRANT_BASIC_PERMISSIONS = Permission._(6, _omitEnumNames ? '' : 'GRANT_BASIC_PERMISSIONS');
  static const Permission VIEW_GROUPS = Permission._(10, _omitEnumNames ? '' : 'VIEW_GROUPS');
  static const Permission CREATE_GROUPS = Permission._(11, _omitEnumNames ? '' : 'CREATE_GROUPS');
  static const Permission PUBLISH_GROUPS_LOCALLY = Permission._(12, _omitEnumNames ? '' : 'PUBLISH_GROUPS_LOCALLY');
  static const Permission PUBLISH_GROUPS_GLOBALLY = Permission._(13, _omitEnumNames ? '' : 'PUBLISH_GROUPS_GLOBALLY');
  static const Permission MODERATE_GROUPS = Permission._(14, _omitEnumNames ? '' : 'MODERATE_GROUPS');
  static const Permission JOIN_GROUPS = Permission._(15, _omitEnumNames ? '' : 'JOIN_GROUPS');
  static const Permission INVITE_GROUP_MEMBERS = Permission._(16, _omitEnumNames ? '' : 'INVITE_GROUP_MEMBERS');
  static const Permission VIEW_POSTS = Permission._(20, _omitEnumNames ? '' : 'VIEW_POSTS');
  static const Permission CREATE_POSTS = Permission._(21, _omitEnumNames ? '' : 'CREATE_POSTS');
  static const Permission PUBLISH_POSTS_LOCALLY = Permission._(22, _omitEnumNames ? '' : 'PUBLISH_POSTS_LOCALLY');
  static const Permission PUBLISH_POSTS_GLOBALLY = Permission._(23, _omitEnumNames ? '' : 'PUBLISH_POSTS_GLOBALLY');
  static const Permission MODERATE_POSTS = Permission._(24, _omitEnumNames ? '' : 'MODERATE_POSTS');
  static const Permission REPLY_TO_POSTS = Permission._(25, _omitEnumNames ? '' : 'REPLY_TO_POSTS');
  static const Permission EDIT_POST_TITLES_AND_LINKS = Permission._(26, _omitEnumNames ? '' : 'EDIT_POST_TITLES_AND_LINKS');
  static const Permission VIEW_EVENTS = Permission._(30, _omitEnumNames ? '' : 'VIEW_EVENTS');
  static const Permission CREATE_EVENTS = Permission._(31, _omitEnumNames ? '' : 'CREATE_EVENTS');
  static const Permission PUBLISH_EVENTS_LOCALLY = Permission._(32, _omitEnumNames ? '' : 'PUBLISH_EVENTS_LOCALLY');
  static const Permission PUBLISH_EVENTS_GLOBALLY = Permission._(33, _omitEnumNames ? '' : 'PUBLISH_EVENTS_GLOBALLY');
  static const Permission MODERATE_EVENTS = Permission._(34, _omitEnumNames ? '' : 'MODERATE_EVENTS');
  static const Permission RSVP_TO_EVENTS = Permission._(35, _omitEnumNames ? '' : 'RSVP_TO_EVENTS');
  static const Permission VIEW_MEDIA = Permission._(40, _omitEnumNames ? '' : 'VIEW_MEDIA');
  static const Permission CREATE_MEDIA = Permission._(41, _omitEnumNames ? '' : 'CREATE_MEDIA');
  static const Permission PUBLISH_MEDIA_LOCALLY = Permission._(42, _omitEnumNames ? '' : 'PUBLISH_MEDIA_LOCALLY');
  static const Permission PUBLISH_MEDIA_GLOBALLY = Permission._(43, _omitEnumNames ? '' : 'PUBLISH_MEDIA_GLOBALLY');
  static const Permission MODERATE_MEDIA = Permission._(44, _omitEnumNames ? '' : 'MODERATE_MEDIA');
  static const Permission READ_PERSONAL_MESSAGES = Permission._(50, _omitEnumNames ? '' : 'READ_PERSONAL_MESSAGES');
  static const Permission READ_ALL_SYSTEM_MESSAGES = Permission._(51, _omitEnumNames ? '' : 'READ_ALL_SYSTEM_MESSAGES');
  static const Permission CREATE_AI_PROVIDERS = Permission._(60, _omitEnumNames ? '' : 'CREATE_AI_PROVIDERS');
  static const Permission SYNC_EVENTS_FROM_ICS = Permission._(700, _omitEnumNames ? '' : 'SYNC_EVENTS_FROM_ICS');
  static const Permission SYNC_POSTS_FROM_RSS = Permission._(701, _omitEnumNames ? '' : 'SYNC_POSTS_FROM_RSS');
  static const Permission SYNC_POSTS_FROM_ATOM = Permission._(702, _omitEnumNames ? '' : 'SYNC_POSTS_FROM_ATOM');
  static const Permission SYNC_EVENTS_TO_FACEBOOK = Permission._(1000, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_FACEBOOK');
  static const Permission SYNC_POSTS_TO_FACEBOOK = Permission._(1001, _omitEnumNames ? '' : 'SYNC_POSTS_TO_FACEBOOK');
  static const Permission SYNC_EVENTS_TO_INSTAGRAM = Permission._(1010, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_INSTAGRAM');
  static const Permission SYNC_POSTS_TO_INSTAGRAM = Permission._(1011, _omitEnumNames ? '' : 'SYNC_POSTS_TO_INSTAGRAM');
  static const Permission SYNC_EVENTS_TO_MASTODON = Permission._(1020, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_MASTODON');
  static const Permission SYNC_POSTS_TO_MASTODON = Permission._(1021, _omitEnumNames ? '' : 'SYNC_POSTS_TO_MASTODON');
  static const Permission SYNC_EVENTS_TO_BLUESKY = Permission._(1030, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_BLUESKY');
  static const Permission SYNC_POSTS_TO_BLUESKY = Permission._(1031, _omitEnumNames ? '' : 'SYNC_POSTS_TO_BLUESKY');
  static const Permission SYNC_EVENTS_TO_X_TWITTER = Permission._(1040, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_X_TWITTER');
  static const Permission SYNC_POSTS_TO_X_TWITTER = Permission._(1041, _omitEnumNames ? '' : 'SYNC_POSTS_TO_X_TWITTER');
  static const Permission SYNC_EVENTS_TO_THREADS = Permission._(1050, _omitEnumNames ? '' : 'SYNC_EVENTS_TO_THREADS');
  static const Permission SYNC_POSTS_TO_THREADS = Permission._(1051, _omitEnumNames ? '' : 'SYNC_POSTS_TO_THREADS');
  static const Permission BUSINESS = Permission._(9998, _omitEnumNames ? '' : 'BUSINESS');
  static const Permission RUN_BOTS = Permission._(9999, _omitEnumNames ? '' : 'RUN_BOTS');
  static const Permission ADMIN = Permission._(10000, _omitEnumNames ? '' : 'ADMIN');
  static const Permission VIEW_PRIVATE_CONTACT_METHODS = Permission._(10001, _omitEnumNames ? '' : 'VIEW_PRIVATE_CONTACT_METHODS');
  static const Permission EDIT_CLUSTER_SETTINGS = Permission._(10002, _omitEnumNames ? '' : 'EDIT_CLUSTER_SETTINGS');
  static const Permission EDIT_SERVER_MEDIA_ALLOCATION = Permission._(10003, _omitEnumNames ? '' : 'EDIT_SERVER_MEDIA_ALLOCATION');

  static const $core.List<Permission> values = <Permission> [
    PERMISSION_UNKNOWN,
    VIEW_USERS,
    PUBLISH_USERS_LOCALLY,
    PUBLISH_USERS_GLOBALLY,
    MODERATE_USERS,
    FOLLOW_USERS,
    GRANT_BASIC_PERMISSIONS,
    VIEW_GROUPS,
    CREATE_GROUPS,
    PUBLISH_GROUPS_LOCALLY,
    PUBLISH_GROUPS_GLOBALLY,
    MODERATE_GROUPS,
    JOIN_GROUPS,
    INVITE_GROUP_MEMBERS,
    VIEW_POSTS,
    CREATE_POSTS,
    PUBLISH_POSTS_LOCALLY,
    PUBLISH_POSTS_GLOBALLY,
    MODERATE_POSTS,
    REPLY_TO_POSTS,
    EDIT_POST_TITLES_AND_LINKS,
    VIEW_EVENTS,
    CREATE_EVENTS,
    PUBLISH_EVENTS_LOCALLY,
    PUBLISH_EVENTS_GLOBALLY,
    MODERATE_EVENTS,
    RSVP_TO_EVENTS,
    VIEW_MEDIA,
    CREATE_MEDIA,
    PUBLISH_MEDIA_LOCALLY,
    PUBLISH_MEDIA_GLOBALLY,
    MODERATE_MEDIA,
    READ_PERSONAL_MESSAGES,
    READ_ALL_SYSTEM_MESSAGES,
    CREATE_AI_PROVIDERS,
    SYNC_EVENTS_FROM_ICS,
    SYNC_POSTS_FROM_RSS,
    SYNC_POSTS_FROM_ATOM,
    SYNC_EVENTS_TO_FACEBOOK,
    SYNC_POSTS_TO_FACEBOOK,
    SYNC_EVENTS_TO_INSTAGRAM,
    SYNC_POSTS_TO_INSTAGRAM,
    SYNC_EVENTS_TO_MASTODON,
    SYNC_POSTS_TO_MASTODON,
    SYNC_EVENTS_TO_BLUESKY,
    SYNC_POSTS_TO_BLUESKY,
    SYNC_EVENTS_TO_X_TWITTER,
    SYNC_POSTS_TO_X_TWITTER,
    SYNC_EVENTS_TO_THREADS,
    SYNC_POSTS_TO_THREADS,
    BUSINESS,
    RUN_BOTS,
    ADMIN,
    VIEW_PRIVATE_CONTACT_METHODS,
    EDIT_CLUSTER_SETTINGS,
    EDIT_SERVER_MEDIA_ALLOCATION,
  ];

  static final $core.Map<$core.int, Permission> _byValue = $pb.ProtobufEnum.initByValue(values);
  static Permission? valueOf($core.int value) => _byValue[value];

  const Permission._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
