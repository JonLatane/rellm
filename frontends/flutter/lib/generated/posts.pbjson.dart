//
//  Generated code. Do not modify.
//  source: posts.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use postListingTypeDescriptor instead')
const PostListingType$json = {
  '1': 'PostListingType',
  '2': [
    {'1': 'ALL_ACCESSIBLE_POSTS', '2': 0},
    {'1': 'FOLLOWING_POSTS', '2': 1},
    {'1': 'MY_GROUPS_POSTS', '2': 2},
    {'1': 'DIRECT_POSTS', '2': 3},
    {'1': 'POSTS_PENDING_MODERATION', '2': 4},
    {'1': 'TEXT_SEARCH', '2': 5},
    {'1': 'GROUP_POSTS', '2': 10},
    {'1': 'GROUP_POSTS_PENDING_MODERATION', '2': 11},
  ],
};

/// Descriptor for `PostListingType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List postListingTypeDescriptor = $convert.base64Decode(
    'Cg9Qb3N0TGlzdGluZ1R5cGUSGAoUQUxMX0FDQ0VTU0lCTEVfUE9TVFMQABITCg9GT0xMT1dJTk'
    'dfUE9TVFMQARITCg9NWV9HUk9VUFNfUE9TVFMQAhIQCgxESVJFQ1RfUE9TVFMQAxIcChhQT1NU'
    'U19QRU5ESU5HX01PREVSQVRJT04QBBIPCgtURVhUX1NFQVJDSBAFEg8KC0dST1VQX1BPU1RTEA'
    'oSIgoeR1JPVVBfUE9TVFNfUEVORElOR19NT0RFUkFUSU9OEAs=');

@$core.Deprecated('Use postContextDescriptor instead')
const PostContext$json = {
  '1': 'PostContext',
  '2': [
    {'1': 'POST', '2': 0},
    {'1': 'REPLY', '2': 1},
    {'1': 'EVENT', '2': 2},
    {'1': 'OCCASION', '2': 3},
    {'1': 'FEDERATED_REPLY', '2': 10},
  ],
};

/// Descriptor for `PostContext`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List postContextDescriptor = $convert.base64Decode(
    'CgtQb3N0Q29udGV4dBIICgRQT1NUEAASCQoFUkVQTFkQARIJCgVFVkVOVBACEgwKCE9DQ0FTSU'
    '9OEAMSEwoPRkVERVJBVEVEX1JFUExZEAo=');

@$core.Deprecated('Use postMediaLayoutDescriptor instead')
const PostMediaLayout$json = {
  '1': 'PostMediaLayout',
  '2': [
    {'1': 'MEDIA_LAYOUT_STANDARD', '2': 0},
    {'1': 'MEDIA_LAYOUT_DYNAMIC_VERTICAL_SCROLL', '2': 1},
  ],
};

/// Descriptor for `PostMediaLayout`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List postMediaLayoutDescriptor = $convert.base64Decode(
    'Cg9Qb3N0TWVkaWFMYXlvdXQSGQoVTUVESUFfTEFZT1VUX1NUQU5EQVJEEAASKAokTUVESUFfTE'
    'FZT1VUX0RZTkFNSUNfVkVSVElDQUxfU0NST0xMEAE=');

@$core.Deprecated('Use getPostsRequestDescriptor instead')
const GetPostsRequest$json = {
  '1': 'GetPostsRequest',
  '2': [
    {'1': 'post_id', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'postId', '17': true},
    {'1': 'author_user_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'authorUserId', '17': true},
    {'1': 'group_id', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'groupId', '17': true},
    {'1': 'reply_depth', '3': 4, '4': 1, '5': 13, '9': 3, '10': 'replyDepth', '17': true},
    {'1': 'context', '3': 5, '4': 1, '5': 14, '6': '.rellm.PostContext', '9': 4, '10': 'context', '17': true},
    {'1': 'post_ids', '3': 9, '4': 1, '5': 9, '9': 5, '10': 'postIds', '17': true},
    {'1': 'listing_type', '3': 10, '4': 1, '5': 14, '6': '.rellm.PostListingType', '10': 'listingType'},
    {'1': 'page', '3': 15, '4': 1, '5': 13, '10': 'page'},
    {'1': 'search_text', '3': 7, '4': 1, '5': 9, '9': 6, '10': 'searchText', '17': true},
    {'1': 'published_or_created_before', '3': 8, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 7, '10': 'publishedOrCreatedBefore', '17': true},
  ],
  '8': [
    {'1': '_post_id'},
    {'1': '_author_user_id'},
    {'1': '_group_id'},
    {'1': '_reply_depth'},
    {'1': '_context'},
    {'1': '_post_ids'},
    {'1': '_search_text'},
    {'1': '_published_or_created_before'},
  ],
};

/// Descriptor for `GetPostsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPostsRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRQb3N0c1JlcXVlc3QSHAoHcG9zdF9pZBgBIAEoCUgAUgZwb3N0SWSIAQESKQoOYXV0aG'
    '9yX3VzZXJfaWQYAiABKAlIAVIMYXV0aG9yVXNlcklkiAEBEh4KCGdyb3VwX2lkGAMgASgJSAJS'
    'B2dyb3VwSWSIAQESJAoLcmVwbHlfZGVwdGgYBCABKA1IA1IKcmVwbHlEZXB0aIgBARIxCgdjb2'
    '50ZXh0GAUgASgOMhIucmVsbG0uUG9zdENvbnRleHRIBFIHY29udGV4dIgBARIeCghwb3N0X2lk'
    'cxgJIAEoCUgFUgdwb3N0SWRziAEBEjkKDGxpc3RpbmdfdHlwZRgKIAEoDjIWLnJlbGxtLlBvc3'
    'RMaXN0aW5nVHlwZVILbGlzdGluZ1R5cGUSEgoEcGFnZRgPIAEoDVIEcGFnZRIkCgtzZWFyY2hf'
    'dGV4dBgHIAEoCUgGUgpzZWFyY2hUZXh0iAEBEl4KG3B1Ymxpc2hlZF9vcl9jcmVhdGVkX2JlZm'
    '9yZRgIIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIB1IYcHVibGlzaGVkT3JDcmVh'
    'dGVkQmVmb3JliAEBQgoKCF9wb3N0X2lkQhEKD19hdXRob3JfdXNlcl9pZEILCglfZ3JvdXBfaW'
    'RCDgoMX3JlcGx5X2RlcHRoQgoKCF9jb250ZXh0QgsKCV9wb3N0X2lkc0IOCgxfc2VhcmNoX3Rl'
    'eHRCHgocX3B1Ymxpc2hlZF9vcl9jcmVhdGVkX2JlZm9yZQ==');

@$core.Deprecated('Use getPostsResponseDescriptor instead')
const GetPostsResponse$json = {
  '1': 'GetPostsResponse',
  '2': [
    {'1': 'posts', '3': 1, '4': 3, '5': 11, '6': '.rellm.Post', '10': 'posts'},
  ],
};

/// Descriptor for `GetPostsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getPostsResponseDescriptor = $convert.base64Decode(
    'ChBHZXRQb3N0c1Jlc3BvbnNlEiEKBXBvc3RzGAEgAygLMgsucmVsbG0uUG9zdFIFcG9zdHM=');

@$core.Deprecated('Use postDescriptor instead')
const Post$json = {
  '1': 'Post',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'author', '3': 2, '4': 1, '5': 11, '6': '.rellm.Author', '9': 0, '10': 'author', '17': true},
    {'1': 'reply_to_post_id', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'replyToPostId', '17': true},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'title', '17': true},
    {'1': 'link', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'link', '17': true},
    {'1': 'content', '3': 6, '4': 1, '5': 9, '9': 4, '10': 'content', '17': true},
    {'1': 'response_count', '3': 7, '4': 1, '5': 5, '10': 'responseCount'},
    {'1': 'reply_count', '3': 8, '4': 1, '5': 5, '10': 'replyCount'},
    {'1': 'group_count', '3': 9, '4': 1, '5': 5, '10': 'groupCount'},
    {'1': 'media', '3': 10, '4': 3, '5': 11, '6': '.rellm.MediaReference', '10': 'media'},
    {'1': 'media_generated', '3': 11, '4': 1, '5': 8, '10': 'mediaGenerated'},
    {'1': 'embed_link', '3': 12, '4': 1, '5': 8, '10': 'embedLink'},
    {'1': 'shareable', '3': 13, '4': 1, '5': 8, '10': 'shareable'},
    {'1': 'context', '3': 14, '4': 1, '5': 14, '6': '.rellm.PostContext', '10': 'context'},
    {'1': 'visibility', '3': 15, '4': 1, '5': 14, '6': '.rellm.Visibility', '10': 'visibility'},
    {'1': 'moderation', '3': 16, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'moderation'},
    {'1': 'post_media_layout', '3': 17, '4': 1, '5': 14, '6': '.rellm.PostMediaLayout', '10': 'postMediaLayout'},
    {'1': 'current_group_post', '3': 18, '4': 1, '5': 11, '6': '.rellm.GroupPost', '9': 5, '10': 'currentGroupPost', '17': true},
    {'1': 'replies', '3': 19, '4': 3, '5': 11, '6': '.rellm.Post', '10': 'replies'},
    {'1': 'created_at', '3': 20, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'updated_at', '3': 21, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 6, '10': 'updatedAt', '17': true},
    {'1': 'published_at', '3': 22, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 7, '10': 'publishedAt', '17': true},
    {'1': 'last_activity_at', '3': 23, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'lastActivityAt'},
    {'1': 'unauthenticated_star_count', '3': 24, '4': 1, '5': 3, '10': 'unauthenticatedStarCount'},
    {'1': 'sync_destinations', '3': 25, '4': 3, '5': 11, '6': '.rellm.SyncDestinationStatus', '10': 'syncDestinations'},
    {'1': 'sync_source', '3': 26, '4': 1, '5': 11, '6': '.rellm.SyncSource', '9': 8, '10': 'syncSource', '17': true},
    {'1': 'quoted_post', '3': 27, '4': 1, '5': 11, '6': '.rellm.Post', '9': 9, '10': 'quotedPost', '17': true},
    {'1': 'quoted_post_id', '3': 28, '4': 1, '5': 9, '9': 10, '10': 'quotedPostId', '17': true},
  ],
  '8': [
    {'1': '_author'},
    {'1': '_reply_to_post_id'},
    {'1': '_title'},
    {'1': '_link'},
    {'1': '_content'},
    {'1': '_current_group_post'},
    {'1': '_updated_at'},
    {'1': '_published_at'},
    {'1': '_sync_source'},
    {'1': '_quoted_post'},
    {'1': '_quoted_post_id'},
  ],
};

/// Descriptor for `Post`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List postDescriptor = $convert.base64Decode(
    'CgRQb3N0Eg4KAmlkGAEgASgJUgJpZBIqCgZhdXRob3IYAiABKAsyDS5yZWxsbS5BdXRob3JIAF'
    'IGYXV0aG9yiAEBEiwKEHJlcGx5X3RvX3Bvc3RfaWQYAyABKAlIAVINcmVwbHlUb1Bvc3RJZIgB'
    'ARIZCgV0aXRsZRgEIAEoCUgCUgV0aXRsZYgBARIXCgRsaW5rGAUgASgJSANSBGxpbmuIAQESHQ'
    'oHY29udGVudBgGIAEoCUgEUgdjb250ZW50iAEBEiUKDnJlc3BvbnNlX2NvdW50GAcgASgFUg1y'
    'ZXNwb25zZUNvdW50Eh8KC3JlcGx5X2NvdW50GAggASgFUgpyZXBseUNvdW50Eh8KC2dyb3VwX2'
    'NvdW50GAkgASgFUgpncm91cENvdW50EisKBW1lZGlhGAogAygLMhUucmVsbG0uTWVkaWFSZWZl'
    'cmVuY2VSBW1lZGlhEicKD21lZGlhX2dlbmVyYXRlZBgLIAEoCFIObWVkaWFHZW5lcmF0ZWQSHQ'
    'oKZW1iZWRfbGluaxgMIAEoCFIJZW1iZWRMaW5rEhwKCXNoYXJlYWJsZRgNIAEoCFIJc2hhcmVh'
    'YmxlEiwKB2NvbnRleHQYDiABKA4yEi5yZWxsbS5Qb3N0Q29udGV4dFIHY29udGV4dBIxCgp2aX'
    'NpYmlsaXR5GA8gASgOMhEucmVsbG0uVmlzaWJpbGl0eVIKdmlzaWJpbGl0eRIxCgptb2RlcmF0'
    'aW9uGBAgASgOMhEucmVsbG0uTW9kZXJhdGlvblIKbW9kZXJhdGlvbhJCChFwb3N0X21lZGlhX2'
    'xheW91dBgRIAEoDjIWLnJlbGxtLlBvc3RNZWRpYUxheW91dFIPcG9zdE1lZGlhTGF5b3V0EkMK'
    'EmN1cnJlbnRfZ3JvdXBfcG9zdBgSIAEoCzIQLnJlbGxtLkdyb3VwUG9zdEgFUhBjdXJyZW50R3'
    'JvdXBQb3N0iAEBEiUKB3JlcGxpZXMYEyADKAsyCy5yZWxsbS5Qb3N0UgdyZXBsaWVzEjkKCmNy'
    'ZWF0ZWRfYXQYFCABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVkQXQSPg'
    'oKdXBkYXRlZF9hdBgVIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIBlIJdXBkYXRl'
    'ZEF0iAEBEkIKDHB1Ymxpc2hlZF9hdBgWIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbX'
    'BIB1ILcHVibGlzaGVkQXSIAQESRAoQbGFzdF9hY3Rpdml0eV9hdBgXIAEoCzIaLmdvb2dsZS5w'
    'cm90b2J1Zi5UaW1lc3RhbXBSDmxhc3RBY3Rpdml0eUF0EjwKGnVuYXV0aGVudGljYXRlZF9zdG'
    'FyX2NvdW50GBggASgDUhh1bmF1dGhlbnRpY2F0ZWRTdGFyQ291bnQSSQoRc3luY19kZXN0aW5h'
    'dGlvbnMYGSADKAsyHC5yZWxsbS5TeW5jRGVzdGluYXRpb25TdGF0dXNSEHN5bmNEZXN0aW5hdG'
    'lvbnMSNwoLc3luY19zb3VyY2UYGiABKAsyES5yZWxsbS5TeW5jU291cmNlSAhSCnN5bmNTb3Vy'
    'Y2WIAQESMQoLcXVvdGVkX3Bvc3QYGyABKAsyCy5yZWxsbS5Qb3N0SAlSCnF1b3RlZFBvc3SIAQ'
    'ESKQoOcXVvdGVkX3Bvc3RfaWQYHCABKAlIClIMcXVvdGVkUG9zdElkiAEBQgkKB19hdXRob3JC'
    'EwoRX3JlcGx5X3RvX3Bvc3RfaWRCCAoGX3RpdGxlQgcKBV9saW5rQgoKCF9jb250ZW50QhUKE1'
    '9jdXJyZW50X2dyb3VwX3Bvc3RCDQoLX3VwZGF0ZWRfYXRCDwoNX3B1Ymxpc2hlZF9hdEIOCgxf'
    'c3luY19zb3VyY2VCDgoMX3F1b3RlZF9wb3N0QhEKD19xdW90ZWRfcG9zdF9pZA==');

@$core.Deprecated('Use syncPostRequestDescriptor instead')
const SyncPostRequest$json = {
  '1': 'SyncPostRequest',
  '2': [
    {'1': 'post_id', '3': 1, '4': 1, '5': 9, '10': 'postId'},
    {'1': 'sync_destination_id', '3': 2, '4': 1, '5': 9, '10': 'syncDestinationId'},
  ],
};

/// Descriptor for `SyncPostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncPostRequestDescriptor = $convert.base64Decode(
    'Cg9TeW5jUG9zdFJlcXVlc3QSFwoHcG9zdF9pZBgBIAEoCVIGcG9zdElkEi4KE3N5bmNfZGVzdG'
    'luYXRpb25faWQYAiABKAlSEXN5bmNEZXN0aW5hdGlvbklk');

@$core.Deprecated('Use deletePostSyncDestinationRequestDescriptor instead')
const DeletePostSyncDestinationRequest$json = {
  '1': 'DeletePostSyncDestinationRequest',
  '2': [
    {'1': 'post_id', '3': 1, '4': 1, '5': 9, '10': 'postId'},
    {'1': 'sync_destination_id', '3': 2, '4': 1, '5': 9, '10': 'syncDestinationId'},
  ],
};

/// Descriptor for `DeletePostSyncDestinationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deletePostSyncDestinationRequestDescriptor = $convert.base64Decode(
    'CiBEZWxldGVQb3N0U3luY0Rlc3RpbmF0aW9uUmVxdWVzdBIXCgdwb3N0X2lkGAEgASgJUgZwb3'
    'N0SWQSLgoTc3luY19kZXN0aW5hdGlvbl9pZBgCIAEoCVIRc3luY0Rlc3RpbmF0aW9uSWQ=');

@$core.Deprecated('Use groupPostDescriptor instead')
const GroupPost$json = {
  '1': 'GroupPost',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 9, '10': 'groupId'},
    {'1': 'post_id', '3': 2, '4': 1, '5': 9, '10': 'postId'},
    {
      '1': 'user_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '8': {'3': true},
      '10': 'userId',
    },
    {'1': 'group_moderation', '3': 4, '4': 1, '5': 14, '6': '.rellm.Moderation', '10': 'groupModeration'},
    {'1': 'created_at', '3': 5, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
    {'1': 'shared_by', '3': 6, '4': 1, '5': 11, '6': '.rellm.Author', '10': 'sharedBy'},
  ],
};

/// Descriptor for `GroupPost`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupPostDescriptor = $convert.base64Decode(
    'CglHcm91cFBvc3QSGQoIZ3JvdXBfaWQYASABKAlSB2dyb3VwSWQSFwoHcG9zdF9pZBgCIAEoCV'
    'IGcG9zdElkEhsKB3VzZXJfaWQYAyABKAlCAhgBUgZ1c2VySWQSPAoQZ3JvdXBfbW9kZXJhdGlv'
    'bhgEIAEoDjIRLnJlbGxtLk1vZGVyYXRpb25SD2dyb3VwTW9kZXJhdGlvbhI5CgpjcmVhdGVkX2'
    'F0GAUgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJY3JlYXRlZEF0EioKCXNoYXJl'
    'ZF9ieRgGIAEoCzINLnJlbGxtLkF1dGhvclIIc2hhcmVkQnk=');

@$core.Deprecated('Use userPostDescriptor instead')
const UserPost$json = {
  '1': 'UserPost',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'post_id', '3': 2, '4': 1, '5': 9, '10': 'postId'},
    {'1': 'created_at', '3': 3, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '10': 'createdAt'},
  ],
};

/// Descriptor for `UserPost`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userPostDescriptor = $convert.base64Decode(
    'CghVc2VyUG9zdBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSFwoHcG9zdF9pZBgCIAEoCVIGcG'
    '9zdElkEjkKCmNyZWF0ZWRfYXQYAyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUglj'
    'cmVhdGVkQXQ=');

@$core.Deprecated('Use getGroupPostsRequestDescriptor instead')
const GetGroupPostsRequest$json = {
  '1': 'GetGroupPostsRequest',
  '2': [
    {'1': 'post_id', '3': 1, '4': 1, '5': 9, '10': 'postId'},
    {'1': 'group_id', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'groupId', '17': true},
  ],
  '8': [
    {'1': '_group_id'},
  ],
};

/// Descriptor for `GetGroupPostsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getGroupPostsRequestDescriptor = $convert.base64Decode(
    'ChRHZXRHcm91cFBvc3RzUmVxdWVzdBIXCgdwb3N0X2lkGAEgASgJUgZwb3N0SWQSHgoIZ3JvdX'
    'BfaWQYAiABKAlIAFIHZ3JvdXBJZIgBAUILCglfZ3JvdXBfaWQ=');

@$core.Deprecated('Use getGroupPostsResponseDescriptor instead')
const GetGroupPostsResponse$json = {
  '1': 'GetGroupPostsResponse',
  '2': [
    {'1': 'group_posts', '3': 1, '4': 3, '5': 11, '6': '.rellm.GroupPost', '10': 'groupPosts'},
  ],
};

/// Descriptor for `GetGroupPostsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getGroupPostsResponseDescriptor = $convert.base64Decode(
    'ChVHZXRHcm91cFBvc3RzUmVzcG9uc2USMQoLZ3JvdXBfcG9zdHMYASADKAsyEC5yZWxsbS5Hcm'
    '91cFBvc3RSCmdyb3VwUG9zdHM=');

