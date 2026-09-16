//
//  Generated code. Do not modify.
//  source: messages.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/timestamp.pb.dart' as $13;
import 'media.pb.dart' as $5;
import 'messages.pbenum.dart';

export 'messages.pbenum.dart';

/// A Rellm `Message` represents a single message/email sent to one or more recipients
/// (really, "zero or more", as the design incorporates undeliverable messages).
class Message extends $pb.GeneratedMessage {
  factory Message({
    $core.String? id,
    $5.Author? sender,
    MessagingGroup? messagingGroup,
    $core.String? bodyText,
    $core.String? subject,
    $core.String? emailMessageId,
    $core.String? from,
    $core.String? to,
    $core.String? cc,
    $core.String? bcc,
    MessageRead? currentUserRead,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (sender != null) {
      $result.sender = sender;
    }
    if (messagingGroup != null) {
      $result.messagingGroup = messagingGroup;
    }
    if (bodyText != null) {
      $result.bodyText = bodyText;
    }
    if (subject != null) {
      $result.subject = subject;
    }
    if (emailMessageId != null) {
      $result.emailMessageId = emailMessageId;
    }
    if (from != null) {
      $result.from = from;
    }
    if (to != null) {
      $result.to = to;
    }
    if (cc != null) {
      $result.cc = cc;
    }
    if (bcc != null) {
      $result.bcc = bcc;
    }
    if (currentUserRead != null) {
      $result.currentUserRead = currentUserRead;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  Message._() : super();
  factory Message.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Message.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Message', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'sender', subBuilder: $5.Author.create)
    ..aOM<MessagingGroup>(3, _omitFieldNames ? '' : 'messagingGroup', subBuilder: MessagingGroup.create)
    ..aOS(4, _omitFieldNames ? '' : 'bodyText')
    ..aOS(5, _omitFieldNames ? '' : 'subject')
    ..aOS(6, _omitFieldNames ? '' : 'emailMessageId')
    ..aOS(7, _omitFieldNames ? '' : 'from')
    ..aOS(8, _omitFieldNames ? '' : 'to')
    ..aOS(9, _omitFieldNames ? '' : 'cc')
    ..aOS(10, _omitFieldNames ? '' : 'bcc')
    ..aOM<MessageRead>(19, _omitFieldNames ? '' : 'currentUserRead', subBuilder: MessageRead.create)
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Message clone() => Message()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Message copyWith(void Function(Message) updates) => super.copyWith((message) => updates(message as Message)) as Message;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Message create() => Message._();
  Message createEmptyInstance() => create();
  static $pb.PbList<Message> createRepeated() => $pb.PbList<Message>();
  @$core.pragma('dart2js:noInline')
  static Message getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Message>(create);
  static Message? _defaultInstance;

  /// The ID of the message.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The sender of the message. Note that this is *purported* (we don't protect against spoofing).
  @$pb.TagNumber(2)
  $5.Author get sender => $_getN(1);
  @$pb.TagNumber(2)
  set sender($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSender() => $_has(1);
  @$pb.TagNumber(2)
  void clearSender() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureSender() => $_ensure(1);

  /// Note that, on the backend, every message actually has a messaging group.
  /// From the client's perspective, if messaging_group is not set, you
  /// were BCC'ed on the message and don't have access to the messaging group.
  @$pb.TagNumber(3)
  MessagingGroup get messagingGroup => $_getN(2);
  @$pb.TagNumber(3)
  set messagingGroup(MessagingGroup v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessagingGroup() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessagingGroup() => clearField(3);
  @$pb.TagNumber(3)
  MessagingGroup ensureMessagingGroup() => $_ensure(2);

  /// The body text of the message. For email messages, this is the email body.
  @$pb.TagNumber(4)
  $core.String get bodyText => $_getSZ(3);
  @$pb.TagNumber(4)
  set bodyText($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasBodyText() => $_has(3);
  @$pb.TagNumber(4)
  void clearBodyText() => clearField(4);

  /// Subject of the message. For email messages, this is the email subject.
  @$pb.TagNumber(5)
  $core.String get subject => $_getSZ(4);
  @$pb.TagNumber(5)
  set subject($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSubject() => $_has(4);
  @$pb.TagNumber(5)
  void clearSubject() => clearField(5);

  /// If this message derived from an email, the original email's message ID (RFC 5322). Used to prevent duplicate messages from being created when the same email is sent multiple times.
  @$pb.TagNumber(6)
  $core.String get emailMessageId => $_getSZ(5);
  @$pb.TagNumber(6)
  set emailMessageId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEmailMessageId() => $_has(5);
  @$pb.TagNumber(6)
  void clearEmailMessageId() => clearField(6);

  /// If this message derived from an email, the original email's "from" address.
  @$pb.TagNumber(7)
  $core.String get from => $_getSZ(6);
  @$pb.TagNumber(7)
  set from($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasFrom() => $_has(6);
  @$pb.TagNumber(7)
  void clearFrom() => clearField(7);

  /// If this message derived from an email, the original email's "to" address.
  @$pb.TagNumber(8)
  $core.String get to => $_getSZ(7);
  @$pb.TagNumber(8)
  set to($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTo() => $_has(7);
  @$pb.TagNumber(8)
  void clearTo() => clearField(8);

  /// If this message derived from an email, the original email's "cc" address.
  @$pb.TagNumber(9)
  $core.String get cc => $_getSZ(8);
  @$pb.TagNumber(9)
  set cc($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasCc() => $_has(8);
  @$pb.TagNumber(9)
  void clearCc() => clearField(9);

  /// If this message derived from an email, the original email's "bcc" address.
  @$pb.TagNumber(10)
  $core.String get bcc => $_getSZ(9);
  @$pb.TagNumber(10)
  set bcc($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasBcc() => $_has(9);
  @$pb.TagNumber(10)
  void clearBcc() => clearField(10);

  /// Whether/when *this response's viewer* has read the message - unset means unread. Always
  /// reflects the currently-authenticated caller's own read status (via [`MarkMessagesRead`](#grpc-api-MarkMessagesRead)), even
  /// when browsing `ALL_SYSTEM_MESSAGES(_TEXT_SEARCH)` as an admin: it's a personal "have I seen
  /// this" marker, not tied to whichever user this response happens to be showing `messaging_group`
  /// for.
  @$pb.TagNumber(19)
  MessageRead get currentUserRead => $_getN(10);
  @$pb.TagNumber(19)
  set currentUserRead(MessageRead v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasCurrentUserRead() => $_has(10);
  @$pb.TagNumber(19)
  void clearCurrentUserRead() => clearField(19);
  @$pb.TagNumber(19)
  MessageRead ensureCurrentUserRead() => $_ensure(10);

  /// The time the message was created.
  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(11);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(11);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(11);
}

/// Records that a user has read a particular Message - one row (conceptually; see the composite
/// `message_id`/`user_id` key on the backing table) per (Message, user) that's ever been marked
/// read. Only ever surfaced back to the user it belongs to, as `Message.current_user_read` - there's
/// no RPC to see *other* users' read status on a Message.
class MessageRead extends $pb.GeneratedMessage {
  factory MessageRead({
    $core.String? messageId,
    $core.String? userId,
    $13.Timestamp? readAt,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (readAt != null) {
      $result.readAt = readAt;
    }
    return $result;
  }
  MessageRead._() : super();
  factory MessageRead.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MessageRead.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MessageRead', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'messageId')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'readAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MessageRead clone() => MessageRead()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MessageRead copyWith(void Function(MessageRead) updates) => super.copyWith((message) => updates(message as MessageRead)) as MessageRead;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessageRead create() => MessageRead._();
  MessageRead createEmptyInstance() => create();
  static $pb.PbList<MessageRead> createRepeated() => $pb.PbList<MessageRead>();
  @$core.pragma('dart2js:noInline')
  static MessageRead getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageRead>(create);
  static MessageRead? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get messageId => $_getSZ(0);
  @$pb.TagNumber(1)
  set messageId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);

  /// When the message was marked read. Always set on a [`MessageRead`](#rellm-MessageRead) returned from [`MarkMessagesRead`](#grpc-api-MarkMessagesRead)
  /// - including a `{ unread: true }` call, where it's simply the time of that unmark request, not
  /// a meaningful "last read" timestamp (there's no longer a row for it to come from at that point).
  @$pb.TagNumber(20)
  $13.Timestamp get readAt => $_getN(2);
  @$pb.TagNumber(20)
  set readAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasReadAt() => $_has(2);
  @$pb.TagNumber(20)
  void clearReadAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureReadAt() => $_ensure(2);
}

/// Marks (or unmarks) one or more Messages as read by the calling user, e.g. every message in a
/// thread once it's been opened. *Authenticated* - read status is inherently personal, so there's
/// no anonymous variant the way [`SendMessage`](#grpc-api-SendMessage) has one.
class MarkMessagesReadRequest extends $pb.GeneratedMessage {
  factory MarkMessagesReadRequest({
    $core.bool? unread,
    $core.Iterable<$core.String>? messageIds,
  }) {
    final $result = create();
    if (unread != null) {
      $result.unread = unread;
    }
    if (messageIds != null) {
      $result.messageIds.addAll(messageIds);
    }
    return $result;
  }
  MarkMessagesReadRequest._() : super();
  factory MarkMessagesReadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarkMessagesReadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarkMessagesReadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'unread')
    ..pPS(2, _omitFieldNames ? '' : 'messageIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarkMessagesReadRequest clone() => MarkMessagesReadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarkMessagesReadRequest copyWith(void Function(MarkMessagesReadRequest) updates) => super.copyWith((message) => updates(message as MarkMessagesReadRequest)) as MarkMessagesReadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarkMessagesReadRequest create() => MarkMessagesReadRequest._();
  MarkMessagesReadRequest createEmptyInstance() => create();
  static $pb.PbList<MarkMessagesReadRequest> createRepeated() => $pb.PbList<MarkMessagesReadRequest>();
  @$core.pragma('dart2js:noInline')
  static MarkMessagesReadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarkMessagesReadRequest>(create);
  static MarkMessagesReadRequest? _defaultInstance;

  /// If `false` (the default), the request is to mark the messages as read. If `true`, marks them
  /// (back) as unread instead - e.g. an explicit "mark unread" action on an already-read message.
  @$pb.TagNumber(1)
  $core.bool get unread => $_getBF(0);
  @$pb.TagNumber(1)
  set unread($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUnread() => $_has(0);
  @$pb.TagNumber(1)
  void clearUnread() => clearField(1);

  /// The Messages to mark read/unread. The caller must have the same access to each of them
  /// [`GetMessages`](#grpc-api-GetMessages) would require (sender, a `messaging_group` member, a Bcc recipient, or an admin)
  /// - see [`MarkMessagesRead`](#grpc-api-MarkMessagesRead)'s own RPC doc comment. A message id the caller doesn't have access to
  /// fails the whole request (see that RPC's own doc on atomicity) rather than silently skipping it.
  @$pb.TagNumber(2)
  $core.List<$core.String> get messageIds => $_getList(1);
}

/// Response to a [`MarkMessagesReadRequest`](#rellm-MarkMessagesReadRequest) - one [`MessageRead`](#rellm-MessageRead) per `message_ids` entry, in the
/// same order, each reflecting that message's own read/unread result (see `MarkMessagesReadRequest.unread`).
class MarkMessagesReadResponse extends $pb.GeneratedMessage {
  factory MarkMessagesReadResponse({
    $core.Iterable<MessageRead>? messageReads,
  }) {
    final $result = create();
    if (messageReads != null) {
      $result.messageReads.addAll(messageReads);
    }
    return $result;
  }
  MarkMessagesReadResponse._() : super();
  factory MarkMessagesReadResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MarkMessagesReadResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MarkMessagesReadResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<MessageRead>(1, _omitFieldNames ? '' : 'messageReads', $pb.PbFieldType.PM, subBuilder: MessageRead.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MarkMessagesReadResponse clone() => MarkMessagesReadResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MarkMessagesReadResponse copyWith(void Function(MarkMessagesReadResponse) updates) => super.copyWith((message) => updates(message as MarkMessagesReadResponse)) as MarkMessagesReadResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarkMessagesReadResponse create() => MarkMessagesReadResponse._();
  MarkMessagesReadResponse createEmptyInstance() => create();
  static $pb.PbList<MarkMessagesReadResponse> createRepeated() => $pb.PbList<MarkMessagesReadResponse>();
  @$core.pragma('dart2js:noInline')
  static MarkMessagesReadResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MarkMessagesReadResponse>(create);
  static MarkMessagesReadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<MessageRead> get messageReads => $_getList(0);
}

/// Request to create a new message.
/// The server will create a new messaging group for the message, and send it to the given recipients.
class SendMessageRequest extends $pb.GeneratedMessage {
  factory SendMessageRequest({
    $core.Iterable<$core.String>? toUserIds,
    $core.String? subject,
    $core.String? bodyText,
  }) {
    final $result = create();
    if (toUserIds != null) {
      $result.toUserIds.addAll(toUserIds);
    }
    if (subject != null) {
      $result.subject = subject;
    }
    if (bodyText != null) {
      $result.bodyText = bodyText;
    }
    return $result;
  }
  SendMessageRequest._() : super();
  factory SendMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SendMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SendMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'toUserIds')
    ..aOS(2, _omitFieldNames ? '' : 'subject')
    ..aOS(3, _omitFieldNames ? '' : 'bodyText')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SendMessageRequest clone() => SendMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SendMessageRequest copyWith(void Function(SendMessageRequest) updates) => super.copyWith((message) => updates(message as SendMessageRequest)) as SendMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendMessageRequest create() => SendMessageRequest._();
  SendMessageRequest createEmptyInstance() => create();
  static $pb.PbList<SendMessageRequest> createRepeated() => $pb.PbList<SendMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static SendMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SendMessageRequest>(create);
  static SendMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get toUserIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get subject => $_getSZ(1);
  @$pb.TagNumber(2)
  set subject($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSubject() => $_has(1);
  @$pb.TagNumber(2)
  void clearSubject() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get bodyText => $_getSZ(2);
  @$pb.TagNumber(3)
  set bodyText($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBodyText() => $_has(2);
  @$pb.TagNumber(3)
  void clearBodyText() => clearField(3);
}

/// A group of users who are participating in a conversation.
/// Most servers will probably have a (dynamically created) "empty group" for an email like
/// `not_a_user@my_rellm_instance.com`.
class MessagingGroup extends $pb.GeneratedMessage {
  factory MessagingGroup({
    $core.String? id,
    $core.Iterable<$5.Author>? members,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (members != null) {
      $result.members.addAll(members);
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  MessagingGroup._() : super();
  factory MessagingGroup.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MessagingGroup.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MessagingGroup', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..pc<$5.Author>(2, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: $5.Author.create)
    ..aOM<$13.Timestamp>(10, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MessagingGroup clone() => MessagingGroup()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MessagingGroup copyWith(void Function(MessagingGroup) updates) => super.copyWith((message) => updates(message as MessagingGroup)) as MessagingGroup;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessagingGroup create() => MessagingGroup._();
  MessagingGroup createEmptyInstance() => create();
  static $pb.PbList<MessagingGroup> createRepeated() => $pb.PbList<MessagingGroup>();
  @$core.pragma('dart2js:noInline')
  static MessagingGroup getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessagingGroup>(create);
  static MessagingGroup? _defaultInstance;

  /// The ID of the messaging group.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The users who are members of the group. Note that this is a superset of the users who are
  @$pb.TagNumber(2)
  $core.List<$5.Author> get members => $_getList(1);

  /// The time the group was created.
  @$pb.TagNumber(10)
  $13.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(10)
  set createdAt($13.Timestamp v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
  @$pb.TagNumber(10)
  $13.Timestamp ensureCreatedAt() => $_ensure(2);
}

/// Request to get messages from the server. The request may be filtered by message ID, search text, or creation time.
/// All non-text-search requests return messages in reverse chronological order (newest first).
/// Text search requests return messages in order of relevance to the search text.
class GetMessagesRequest extends $pb.GeneratedMessage {
  factory GetMessagesRequest({
    MessageListingType? listingType,
    $core.String? messageId,
    $core.String? messageGroupId,
    $core.String? searchText,
    $13.Timestamp? sentBefore,
    $core.String? fromEmail,
  }) {
    final $result = create();
    if (listingType != null) {
      $result.listingType = listingType;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (messageGroupId != null) {
      $result.messageGroupId = messageGroupId;
    }
    if (searchText != null) {
      $result.searchText = searchText;
    }
    if (sentBefore != null) {
      $result.sentBefore = sentBefore;
    }
    if (fromEmail != null) {
      $result.fromEmail = fromEmail;
    }
    return $result;
  }
  GetMessagesRequest._() : super();
  factory GetMessagesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMessagesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMessagesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..e<MessageListingType>(1, _omitFieldNames ? '' : 'listingType', $pb.PbFieldType.OE, defaultOrMaker: MessageListingType.PERSONAL_MESSAGES, valueOf: MessageListingType.valueOf, enumValues: MessageListingType.values)
    ..aOS(2, _omitFieldNames ? '' : 'messageId')
    ..aOS(3, _omitFieldNames ? '' : 'messageGroupId')
    ..aOS(7, _omitFieldNames ? '' : 'searchText')
    ..aOM<$13.Timestamp>(8, _omitFieldNames ? '' : 'sentBefore', subBuilder: $13.Timestamp.create)
    ..aOS(9, _omitFieldNames ? '' : 'fromEmail')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMessagesRequest clone() => GetMessagesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMessagesRequest copyWith(void Function(GetMessagesRequest) updates) => super.copyWith((message) => updates(message as GetMessagesRequest)) as GetMessagesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMessagesRequest create() => GetMessagesRequest._();
  GetMessagesRequest createEmptyInstance() => create();
  static $pb.PbList<GetMessagesRequest> createRepeated() => $pb.PbList<GetMessagesRequest>();
  @$core.pragma('dart2js:noInline')
  static GetMessagesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMessagesRequest>(create);
  static GetMessagesRequest? _defaultInstance;

  /// The type of message listing to return. Required.
  @$pb.TagNumber(1)
  MessageListingType get listingType => $_getN(0);
  @$pb.TagNumber(1)
  set listingType(MessageListingType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasListingType() => $_has(0);
  @$pb.TagNumber(1)
  void clearListingType() => clearField(1);

  /// Returns the single message with the given ID (assuming the user has access to it).
  @$pb.TagNumber(2)
  $core.String get messageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set messageId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => clearField(2);

  /// Returns messages that are part of the given messaging group (assuming the user has access to it).
  @$pb.TagNumber(3)
  $core.String get messageGroupId => $_getSZ(2);
  @$pb.TagNumber(3)
  set messageGroupId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessageGroupId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessageGroupId() => clearField(3);

  /// Full-text search query, matched against the sender's username/real name and the message's
  /// subject and body. Required (and only used) when `listing_type` is `TEXT_SEARCH`.
  @$pb.TagNumber(7)
  $core.String get searchText => $_getSZ(3);
  @$pb.TagNumber(7)
  set searchText($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(7)
  $core.bool hasSearchText() => $_has(3);
  @$pb.TagNumber(7)
  void clearSearchText() => clearField(7);

  /// Request to only return posts that were published or created before the given timestamp.
  @$pb.TagNumber(8)
  $13.Timestamp get sentBefore => $_getN(4);
  @$pb.TagNumber(8)
  set sentBefore($13.Timestamp v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasSentBefore() => $_has(4);
  @$pb.TagNumber(8)
  void clearSentBefore() => clearField(8);
  @$pb.TagNumber(8)
  $13.Timestamp ensureSentBefore() => $_ensure(4);

  /// Returns messages (assuming the user has access to each) whose email "from" header exactly
  /// matches the given value - i.e. `Message.from` as returned by a previous response. Meant for
  /// expanding the "sender" grouping a client falls back to when `Message.messaging_group` isn't
  /// set (see that field's own doc comment): unlike `message_group_id`, there's no server-side
  /// group backing this, so it's just a straight filter, not an access-controlled entity lookup.
  /// Since `from` is unauthenticated/spoofable (see this file's own top-level doc comment), so is
  /// this filter - it matches whatever string the sender's email client sent, nothing more.
  @$pb.TagNumber(9)
  $core.String get fromEmail => $_getSZ(5);
  @$pb.TagNumber(9)
  set fromEmail($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(9)
  $core.bool hasFromEmail() => $_has(5);
  @$pb.TagNumber(9)
  void clearFromEmail() => clearField(9);
}

/// Response to a [`GetMessagesRequest`](#rellm-GetMessagesRequest), containing the requested messages.
class GetMessagesResponse extends $pb.GeneratedMessage {
  factory GetMessagesResponse({
    $core.Iterable<Message>? messages,
  }) {
    final $result = create();
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    return $result;
  }
  GetMessagesResponse._() : super();
  factory GetMessagesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMessagesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMessagesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<Message>(1, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: Message.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMessagesResponse clone() => GetMessagesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMessagesResponse copyWith(void Function(GetMessagesResponse) updates) => super.copyWith((message) => updates(message as GetMessagesResponse)) as GetMessagesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMessagesResponse create() => GetMessagesResponse._();
  GetMessagesResponse createEmptyInstance() => create();
  static $pb.PbList<GetMessagesResponse> createRepeated() => $pb.PbList<GetMessagesResponse>();
  @$core.pragma('dart2js:noInline')
  static GetMessagesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMessagesResponse>(create);
  static GetMessagesResponse? _defaultInstance;

  /// The messages that match the request. May be empty if no messages match.
  /// May be shortened to a server-defined limit, dependent on service version,
  /// configuration, load, etc.
  @$pb.TagNumber(1)
  $core.List<Message> get messages => $_getList(0);
}

/// A browser's Web Push subscription (see https://developer.mozilla.org/en-US/docs/Web/API/Push_API),
/// registered so the server can push new-Message notifications to it even while the browser tab is
/// closed. Only ever surfaced back to the user who registered it - there's no RPC to list other
/// users' subscriptions.
class PushSubscription extends $pb.GeneratedMessage {
  factory PushSubscription({
    $core.String? id,
    $core.String? endpoint,
    $13.Timestamp? createdAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (endpoint != null) {
      $result.endpoint = endpoint;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  PushSubscription._() : super();
  factory PushSubscription.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PushSubscription.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PushSubscription', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'endpoint')
    ..aOM<$13.Timestamp>(20, _omitFieldNames ? '' : 'createdAt', subBuilder: $13.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PushSubscription clone() => PushSubscription()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PushSubscription copyWith(void Function(PushSubscription) updates) => super.copyWith((message) => updates(message as PushSubscription)) as PushSubscription;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PushSubscription create() => PushSubscription._();
  PushSubscription createEmptyInstance() => create();
  static $pb.PbList<PushSubscription> createRepeated() => $pb.PbList<PushSubscription>();
  @$core.pragma('dart2js:noInline')
  static PushSubscription getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PushSubscription>(create);
  static PushSubscription? _defaultInstance;

  /// The ID of the subscription.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The Web Push subscription endpoint URL, as given by `PushManager.subscribe()`.
  @$pb.TagNumber(2)
  $core.String get endpoint => $_getSZ(1);
  @$pb.TagNumber(2)
  set endpoint($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEndpoint() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndpoint() => clearField(2);

  /// The time the subscription was registered.
  @$pb.TagNumber(20)
  $13.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(20)
  set createdAt($13.Timestamp v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(20)
  void clearCreatedAt() => clearField(20);
  @$pb.TagNumber(20)
  $13.Timestamp ensureCreatedAt() => $_ensure(2);
}

/// Registers (or re-registers) a browser's Web Push subscription for the current user, so new
/// Messages sent/delivered to them push a notification even while the browser tab is closed.
/// See [`RegisterPushSubscription`](#grpc-api-RegisterPushSubscription)'s own RPC doc comment.
class RegisterPushSubscriptionRequest extends $pb.GeneratedMessage {
  factory RegisterPushSubscriptionRequest({
    $core.String? endpoint,
    $core.String? p256dhKey,
    $core.String? authKey,
  }) {
    final $result = create();
    if (endpoint != null) {
      $result.endpoint = endpoint;
    }
    if (p256dhKey != null) {
      $result.p256dhKey = p256dhKey;
    }
    if (authKey != null) {
      $result.authKey = authKey;
    }
    return $result;
  }
  RegisterPushSubscriptionRequest._() : super();
  factory RegisterPushSubscriptionRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RegisterPushSubscriptionRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RegisterPushSubscriptionRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'endpoint')
    ..aOS(2, _omitFieldNames ? '' : 'p256dhKey')
    ..aOS(3, _omitFieldNames ? '' : 'authKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RegisterPushSubscriptionRequest clone() => RegisterPushSubscriptionRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RegisterPushSubscriptionRequest copyWith(void Function(RegisterPushSubscriptionRequest) updates) => super.copyWith((message) => updates(message as RegisterPushSubscriptionRequest)) as RegisterPushSubscriptionRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterPushSubscriptionRequest create() => RegisterPushSubscriptionRequest._();
  RegisterPushSubscriptionRequest createEmptyInstance() => create();
  static $pb.PbList<RegisterPushSubscriptionRequest> createRepeated() => $pb.PbList<RegisterPushSubscriptionRequest>();
  @$core.pragma('dart2js:noInline')
  static RegisterPushSubscriptionRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RegisterPushSubscriptionRequest>(create);
  static RegisterPushSubscriptionRequest? _defaultInstance;

  /// The Web Push subscription endpoint URL, as given by `PushManager.subscribe()`.
  @$pb.TagNumber(1)
  $core.String get endpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set endpoint($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearEndpoint() => clearField(1);

  /// The subscription's `p256dh` key (base64url), as given by `PushSubscription.getKey('p256dh')`.
  @$pb.TagNumber(2)
  $core.String get p256dhKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set p256dhKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasP256dhKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearP256dhKey() => clearField(2);

  /// The subscription's `auth` key (base64url), as given by `PushSubscription.getKey('auth')`.
  @$pb.TagNumber(3)
  $core.String get authKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set authKey($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAuthKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthKey() => clearField(3);
}

/// Unregisters a browser's Web Push subscription for the current user, e.g. on logout or when
/// `PushManager.subscribe()` reports the subscription as no longer valid. See
/// [`UnregisterPushSubscription`](#grpc-api-UnregisterPushSubscription)'s own RPC doc comment.
class UnregisterPushSubscriptionRequest extends $pb.GeneratedMessage {
  factory UnregisterPushSubscriptionRequest({
    $core.String? endpoint,
  }) {
    final $result = create();
    if (endpoint != null) {
      $result.endpoint = endpoint;
    }
    return $result;
  }
  UnregisterPushSubscriptionRequest._() : super();
  factory UnregisterPushSubscriptionRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UnregisterPushSubscriptionRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UnregisterPushSubscriptionRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'endpoint')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UnregisterPushSubscriptionRequest clone() => UnregisterPushSubscriptionRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UnregisterPushSubscriptionRequest copyWith(void Function(UnregisterPushSubscriptionRequest) updates) => super.copyWith((message) => updates(message as UnregisterPushSubscriptionRequest)) as UnregisterPushSubscriptionRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnregisterPushSubscriptionRequest create() => UnregisterPushSubscriptionRequest._();
  UnregisterPushSubscriptionRequest createEmptyInstance() => create();
  static $pb.PbList<UnregisterPushSubscriptionRequest> createRepeated() => $pb.PbList<UnregisterPushSubscriptionRequest>();
  @$core.pragma('dart2js:noInline')
  static UnregisterPushSubscriptionRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UnregisterPushSubscriptionRequest>(create);
  static UnregisterPushSubscriptionRequest? _defaultInstance;

  /// The Web Push subscription endpoint URL to unregister, as previously passed to
  /// [`RegisterPushSubscription`](#grpc-api-RegisterPushSubscription).
  @$pb.TagNumber(1)
  $core.String get endpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set endpoint($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearEndpoint() => clearField(1);
}

/// Checks whether the current user has already registered a given Web Push subscription endpoint.
/// See [`GetPushSubscriptionStatus`](#grpc-api-GetPushSubscriptionStatus)'s own RPC doc comment.
class GetPushSubscriptionStatusRequest extends $pb.GeneratedMessage {
  factory GetPushSubscriptionStatusRequest({
    $core.String? endpoint,
  }) {
    final $result = create();
    if (endpoint != null) {
      $result.endpoint = endpoint;
    }
    return $result;
  }
  GetPushSubscriptionStatusRequest._() : super();
  factory GetPushSubscriptionStatusRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetPushSubscriptionStatusRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPushSubscriptionStatusRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'endpoint')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetPushSubscriptionStatusRequest clone() => GetPushSubscriptionStatusRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetPushSubscriptionStatusRequest copyWith(void Function(GetPushSubscriptionStatusRequest) updates) => super.copyWith((message) => updates(message as GetPushSubscriptionStatusRequest)) as GetPushSubscriptionStatusRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPushSubscriptionStatusRequest create() => GetPushSubscriptionStatusRequest._();
  GetPushSubscriptionStatusRequest createEmptyInstance() => create();
  static $pb.PbList<GetPushSubscriptionStatusRequest> createRepeated() => $pb.PbList<GetPushSubscriptionStatusRequest>();
  @$core.pragma('dart2js:noInline')
  static GetPushSubscriptionStatusRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPushSubscriptionStatusRequest>(create);
  static GetPushSubscriptionStatusRequest? _defaultInstance;

  /// The Web Push subscription endpoint URL to check, as given by `PushManager.subscribe()`.
  @$pb.TagNumber(1)
  $core.String get endpoint => $_getSZ(0);
  @$pb.TagNumber(1)
  set endpoint($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEndpoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearEndpoint() => clearField(1);
}

class GetPushSubscriptionStatusResponse extends $pb.GeneratedMessage {
  factory GetPushSubscriptionStatusResponse({
    $core.bool? registered,
  }) {
    final $result = create();
    if (registered != null) {
      $result.registered = registered;
    }
    return $result;
  }
  GetPushSubscriptionStatusResponse._() : super();
  factory GetPushSubscriptionStatusResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetPushSubscriptionStatusResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetPushSubscriptionStatusResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'registered')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetPushSubscriptionStatusResponse clone() => GetPushSubscriptionStatusResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetPushSubscriptionStatusResponse copyWith(void Function(GetPushSubscriptionStatusResponse) updates) => super.copyWith((message) => updates(message as GetPushSubscriptionStatusResponse)) as GetPushSubscriptionStatusResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetPushSubscriptionStatusResponse create() => GetPushSubscriptionStatusResponse._();
  GetPushSubscriptionStatusResponse createEmptyInstance() => create();
  static $pb.PbList<GetPushSubscriptionStatusResponse> createRepeated() => $pb.PbList<GetPushSubscriptionStatusResponse>();
  @$core.pragma('dart2js:noInline')
  static GetPushSubscriptionStatusResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetPushSubscriptionStatusResponse>(create);
  static GetPushSubscriptionStatusResponse? _defaultInstance;

  /// Whether the current user has a [`PushSubscription`](#rellm-PushSubscription) registered for this exact `endpoint`.
  @$pb.TagNumber(1)
  $core.bool get registered => $_getBF(0);
  @$pb.TagNumber(1)
  set registered($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRegistered() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistered() => clearField(1);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
