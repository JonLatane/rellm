//
//  Generated code. Do not modify.
//  source: visibility_moderation.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

///  Visibility in Rellm is a complex topic. There are several different types of visibility,
///  and each type of entity ([`User`](#rellm-User), [`Media`](#rellm-Media), [`Group`](#rellm-Group), then [`Post`](#rellm-Post)/[`Event`](#rellm-Event)/etc. with common logic)
///  has different rules for visibility.
///
///  From the top down, the rules break down as follows:
///
///  - Even a `PRIVATE` entity is always visible to the user who owns it.
///      - For [`Group`](#rellm-Group)s, this means all full members of the [`Group`](#rellm-Group).
///      - For [`User`](#rellm-User)s, this is confusing and there is a whole [`PrivateUserStrategy`](#rellm-PrivateUserStrategy) thing
///        in [`ServerConfiguration`](#rellm-ServerConfiguration) for this.
///  - A `LIMITED` entity is visible to to the owner(s) and any explicitly associated
///    [`User`](#rellm-User)s and [`Group`](#rellm-Group)s. Generally, this only applies to [`Post`](#rellm-Post)/[`Event`](#rellm-Event)/etc. entities.
///    Associations exist via [`UserPost`](#rellm-UserPost)s and [`GroupPost`](#rellm-GroupPost)s.
///      - This is currently only implemented for [`Group`](#rellm-Group)s and [`GroupPost`](#rellm-GroupPost)s. There are some
///        choices to be made about how to implement this for [`User`](#rellm-User)s and [`UserPost`](#rellm-UserPost)s, and whether
///        `DIRECT` should be a separate visibility type.
///  - A `SERVER_PUBLIC` entity is visible to all authenticated users.
///  - A `GLOBAL_PUBLIC` entity is visible to the open internet.
class Visibility extends $pb.ProtobufEnum {
  static const Visibility VISIBILITY_UNKNOWN = Visibility._(0, _omitEnumNames ? '' : 'VISIBILITY_UNKNOWN');
  static const Visibility PRIVATE = Visibility._(1, _omitEnumNames ? '' : 'PRIVATE');
  static const Visibility LIMITED = Visibility._(2, _omitEnumNames ? '' : 'LIMITED');
  static const Visibility SERVER_PUBLIC = Visibility._(3, _omitEnumNames ? '' : 'SERVER_PUBLIC');
  static const Visibility GLOBAL_PUBLIC = Visibility._(4, _omitEnumNames ? '' : 'GLOBAL_PUBLIC');
  static const Visibility DIRECT = Visibility._(5, _omitEnumNames ? '' : 'DIRECT');
  static const Visibility LICENSED = Visibility._(6, _omitEnumNames ? '' : 'LICENSED');

  static const $core.List<Visibility> values = <Visibility> [
    VISIBILITY_UNKNOWN,
    PRIVATE,
    LIMITED,
    SERVER_PUBLIC,
    GLOBAL_PUBLIC,
    DIRECT,
    LICENSED,
  ];

  static final $core.Map<$core.int, Visibility> _byValue = $pb.ProtobufEnum.initByValue(values);
  static Visibility? valueOf($core.int value) => _byValue[value];

  const Visibility._($core.int v, $core.String n) : super(v, n);
}

///  Nearly everything in Rellm has one or more `Moderation`s on it.
///
///  From a high level:
///
///  - A [`User`](#rellm-User) has a `moderation` that determines whether they can log in (and their visibility per their `visibility`).
///    (This is poorly enforced currently! Fix it if you want!)
///      - This is managed by `people_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
///        A default of `UNMODERATED` means that all users can log in. A default of `PENDING`
///        means that all users must be approved by a moderator/admin before they can log in.
///  - A [`Follow`](#rellm-Follow) has a `target_user_moderation` that determines whether the [`User`](#rellm-User) is following the [`Group`](#rellm-Group).
///     - It is managed by `default_follow_moderation` in the targeted [`User`](#rellm-User).
///  - A [`Group`](#rellm-Group) has a `moderation` that determines whether the [`Group`](#rellm-Group) is visible to users (per its `visibility`).
///      - This is managed by `group_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
///  - A [`Membership`](#rellm-Membership) has a `group_moderation` and `user_moderation` that determine whether
///    the [`Group`](#rellm-Group) admins and/or the invited user has approved the [`Membership`](#rellm-Membership), respectively.
///      - User invites to [`Group`](#rellm-Group)s (i.e. the `user_moderation`) always start as `PENDING`.
///        The group side of this is managed by `default_membership_moderation` of the [`Group`](#rellm-Group) in question.
///  - A [`Post`](#rellm-Post) has a `moderation` that determines whether the [`Post`](#rellm-Post) is visible to users (per its `visibility`).
///      - This is managed by `post_settings.default_moderation` in [`ServerConfiguration`](#rellm-ServerConfiguration).
///  - A [`GroupPost`](#rellm-GroupPost) has a `moderation` that determines whether the admins/mods of the [`Group`](#rellm-Group) has approved the [`Post`](#rellm-Post) (or [`Post`](#rellm-Post)-descended thing like [`Event`](#rellm-Event)s).
///  - [`Event`](#rellm-Event)s and further objects contain a [`Post`](#rellm-Post) and thus inherit its `moderation` and
///    related [`GroupPost`](#rellm-GroupPost) behavior, for "Group Events."
class Moderation extends $pb.ProtobufEnum {
  static const Moderation MODERATION_UNKNOWN = Moderation._(0, _omitEnumNames ? '' : 'MODERATION_UNKNOWN');
  static const Moderation UNMODERATED = Moderation._(1, _omitEnumNames ? '' : 'UNMODERATED');
  static const Moderation PENDING = Moderation._(2, _omitEnumNames ? '' : 'PENDING');
  static const Moderation APPROVED = Moderation._(3, _omitEnumNames ? '' : 'APPROVED');
  static const Moderation REJECTED = Moderation._(4, _omitEnumNames ? '' : 'REJECTED');

  static const $core.List<Moderation> values = <Moderation> [
    MODERATION_UNKNOWN,
    UNMODERATED,
    PENDING,
    APPROVED,
    REJECTED,
  ];

  static final $core.Map<$core.int, Moderation> _byValue = $pb.ProtobufEnum.initByValue(values);
  static Moderation? valueOf($core.int value) => _byValue[value];

  const Moderation._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
