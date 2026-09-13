//
//  Generated code. Do not modify.
//  source: rellm.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'ai_providers.pb.dart' as $11;
import 'authentication.pb.dart' as $3;
import 'events.pb.dart' as $9;
import 'federation.pb.dart' as $1;
import 'google/protobuf/empty.pb.dart' as $0;
import 'groups.pb.dart' as $7;
import 'media.pb.dart' as $5;
import 'messages.pb.dart' as $6;
import 'posts.pb.dart' as $8;
import 'server_configuration.pb.dart' as $2;
import 'sync.pb.dart' as $10;
import 'users.pb.dart' as $4;

export 'rellm.pb.dart';

@$pb.GrpcServiceName('rellm.Rellm')
class RellmClient extends $grpc.Client {
  static final _$getServiceVersion = $grpc.ClientMethod<$0.Empty, $1.GetServiceVersionResponse>(
      '/rellm.Rellm/GetServiceVersion',
      ($0.Empty value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.GetServiceVersionResponse.fromBuffer(value));
  static final _$getServerConfiguration = $grpc.ClientMethod<$0.Empty, $2.ServerConfiguration>(
      '/rellm.Rellm/GetServerConfiguration',
      ($0.Empty value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.ServerConfiguration.fromBuffer(value));
  static final _$createAccount = $grpc.ClientMethod<$3.CreateAccountRequest, $3.RefreshTokenResponse>(
      '/rellm.Rellm/CreateAccount',
      ($3.CreateAccountRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $3.RefreshTokenResponse.fromBuffer(value));
  static final _$login = $grpc.ClientMethod<$3.LoginRequest, $3.RefreshTokenResponse>(
      '/rellm.Rellm/Login',
      ($3.LoginRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $3.RefreshTokenResponse.fromBuffer(value));
  static final _$accessToken = $grpc.ClientMethod<$3.AccessTokenRequest, $3.AccessTokenResponse>(
      '/rellm.Rellm/AccessToken',
      ($3.AccessTokenRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $3.AccessTokenResponse.fromBuffer(value));
  static final _$getCurrentUser = $grpc.ClientMethod<$0.Empty, $4.User>(
      '/rellm.Rellm/GetCurrentUser',
      ($0.Empty value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.User.fromBuffer(value));
  static final _$resetPassword = $grpc.ClientMethod<$3.ResetPasswordRequest, $0.Empty>(
      '/rellm.Rellm/ResetPassword',
      ($3.ResetPasswordRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getMedia = $grpc.ClientMethod<$5.GetMediaRequest, $5.GetMediaResponse>(
      '/rellm.Rellm/GetMedia',
      ($5.GetMediaRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $5.GetMediaResponse.fromBuffer(value));
  static final _$deleteMedia = $grpc.ClientMethod<$5.Media, $0.Empty>(
      '/rellm.Rellm/DeleteMedia',
      ($5.Media value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$updateMedia = $grpc.ClientMethod<$5.Media, $5.Media>(
      '/rellm.Rellm/UpdateMedia',
      ($5.Media value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $5.Media.fromBuffer(value));
  static final _$deleteMediaSizes = $grpc.ClientMethod<$5.Media, $5.Media>(
      '/rellm.Rellm/DeleteMediaSizes',
      ($5.Media value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $5.Media.fromBuffer(value));
  static final _$getUsers = $grpc.ClientMethod<$4.GetUsersRequest, $4.GetUsersResponse>(
      '/rellm.Rellm/GetUsers',
      ($4.GetUsersRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.GetUsersResponse.fromBuffer(value));
  static final _$updateUser = $grpc.ClientMethod<$4.User, $4.User>(
      '/rellm.Rellm/UpdateUser',
      ($4.User value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.User.fromBuffer(value));
  static final _$startContactMethodVerification = $grpc.ClientMethod<$4.ContactMethod, $4.ContactMethod>(
      '/rellm.Rellm/StartContactMethodVerification',
      ($4.ContactMethod value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.ContactMethod.fromBuffer(value));
  static final _$verifyContactMethod = $grpc.ClientMethod<$4.VerifyContactMethodRequest, $4.ContactMethod>(
      '/rellm.Rellm/VerifyContactMethod',
      ($4.VerifyContactMethodRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.ContactMethod.fromBuffer(value));
  static final _$deleteUser = $grpc.ClientMethod<$4.User, $0.Empty>(
      '/rellm.Rellm/DeleteUser',
      ($4.User value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$sendMessage = $grpc.ClientMethod<$6.SendMessageRequest, $6.Message>(
      '/rellm.Rellm/SendMessage',
      ($6.SendMessageRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.Message.fromBuffer(value));
  static final _$getMessages = $grpc.ClientMethod<$6.GetMessagesRequest, $6.GetMessagesResponse>(
      '/rellm.Rellm/GetMessages',
      ($6.GetMessagesRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.GetMessagesResponse.fromBuffer(value));
  static final _$markMessagesRead = $grpc.ClientMethod<$6.MarkMessagesReadRequest, $6.MarkMessagesReadResponse>(
      '/rellm.Rellm/MarkMessagesRead',
      ($6.MarkMessagesReadRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.MarkMessagesReadResponse.fromBuffer(value));
  static final _$registerPushSubscription = $grpc.ClientMethod<$6.RegisterPushSubscriptionRequest, $6.PushSubscription>(
      '/rellm.Rellm/RegisterPushSubscription',
      ($6.RegisterPushSubscriptionRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.PushSubscription.fromBuffer(value));
  static final _$unregisterPushSubscription = $grpc.ClientMethod<$6.UnregisterPushSubscriptionRequest, $0.Empty>(
      '/rellm.Rellm/UnregisterPushSubscription',
      ($6.UnregisterPushSubscriptionRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getPushSubscriptionStatus = $grpc.ClientMethod<$6.GetPushSubscriptionStatusRequest, $6.GetPushSubscriptionStatusResponse>(
      '/rellm.Rellm/GetPushSubscriptionStatus',
      ($6.GetPushSubscriptionStatusRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $6.GetPushSubscriptionStatusResponse.fromBuffer(value));
  static final _$createFollow = $grpc.ClientMethod<$4.Follow, $4.Follow>(
      '/rellm.Rellm/CreateFollow',
      ($4.Follow value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.Follow.fromBuffer(value));
  static final _$updateFollow = $grpc.ClientMethod<$4.Follow, $4.Follow>(
      '/rellm.Rellm/UpdateFollow',
      ($4.Follow value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.Follow.fromBuffer(value));
  static final _$deleteFollow = $grpc.ClientMethod<$4.Follow, $0.Empty>(
      '/rellm.Rellm/DeleteFollow',
      ($4.Follow value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getGroups = $grpc.ClientMethod<$7.GetGroupsRequest, $7.GetGroupsResponse>(
      '/rellm.Rellm/GetGroups',
      ($7.GetGroupsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.GetGroupsResponse.fromBuffer(value));
  static final _$createGroup = $grpc.ClientMethod<$7.Group, $7.Group>(
      '/rellm.Rellm/CreateGroup',
      ($7.Group value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.Group.fromBuffer(value));
  static final _$updateGroup = $grpc.ClientMethod<$7.Group, $7.Group>(
      '/rellm.Rellm/UpdateGroup',
      ($7.Group value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.Group.fromBuffer(value));
  static final _$deleteGroup = $grpc.ClientMethod<$7.Group, $0.Empty>(
      '/rellm.Rellm/DeleteGroup',
      ($7.Group value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getMembers = $grpc.ClientMethod<$7.GetMembersRequest, $7.GetMembersResponse>(
      '/rellm.Rellm/GetMembers',
      ($7.GetMembersRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $7.GetMembersResponse.fromBuffer(value));
  static final _$createMembership = $grpc.ClientMethod<$4.Membership, $4.Membership>(
      '/rellm.Rellm/CreateMembership',
      ($4.Membership value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.Membership.fromBuffer(value));
  static final _$updateMembership = $grpc.ClientMethod<$4.Membership, $4.Membership>(
      '/rellm.Rellm/UpdateMembership',
      ($4.Membership value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $4.Membership.fromBuffer(value));
  static final _$deleteMembership = $grpc.ClientMethod<$4.Membership, $0.Empty>(
      '/rellm.Rellm/DeleteMembership',
      ($4.Membership value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getPosts = $grpc.ClientMethod<$8.GetPostsRequest, $8.GetPostsResponse>(
      '/rellm.Rellm/GetPosts',
      ($8.GetPostsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.GetPostsResponse.fromBuffer(value));
  static final _$createPost = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/CreatePost',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$updatePost = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/UpdatePost',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$deletePost = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/DeletePost',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$starPost = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/StarPost',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$unstarPost = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/UnstarPost',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$syncPost = $grpc.ClientMethod<$8.SyncPostRequest, $8.Post>(
      '/rellm.Rellm/SyncPost',
      ($8.SyncPostRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));
  static final _$deletePostSyncDestination = $grpc.ClientMethod<$8.DeletePostSyncDestinationRequest, $0.Empty>(
      '/rellm.Rellm/DeletePostSyncDestination',
      ($8.DeletePostSyncDestinationRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getGroupPosts = $grpc.ClientMethod<$8.GetGroupPostsRequest, $8.GetGroupPostsResponse>(
      '/rellm.Rellm/GetGroupPosts',
      ($8.GetGroupPostsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.GetGroupPostsResponse.fromBuffer(value));
  static final _$createGroupPost = $grpc.ClientMethod<$8.GroupPost, $8.GroupPost>(
      '/rellm.Rellm/CreateGroupPost',
      ($8.GroupPost value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.GroupPost.fromBuffer(value));
  static final _$updateGroupPost = $grpc.ClientMethod<$8.GroupPost, $8.GroupPost>(
      '/rellm.Rellm/UpdateGroupPost',
      ($8.GroupPost value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.GroupPost.fromBuffer(value));
  static final _$deleteGroupPost = $grpc.ClientMethod<$8.GroupPost, $0.Empty>(
      '/rellm.Rellm/DeleteGroupPost',
      ($8.GroupPost value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getEvents = $grpc.ClientMethod<$9.GetEventsRequest, $9.GetEventsResponse>(
      '/rellm.Rellm/GetEvents',
      ($9.GetEventsRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.GetEventsResponse.fromBuffer(value));
  static final _$createEvent = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/CreateEvent',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$updateEvent = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/UpdateEvent',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$deleteEvent = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/DeleteEvent',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$updateEventDetails = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/UpdateEventDetails',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$createNewOccasions = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/CreateNewOccasions',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$updateOccasions = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/UpdateOccasions',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$deleteRemovedOccasions = $grpc.ClientMethod<$9.Event, $9.Event>(
      '/rellm.Rellm/DeleteRemovedOccasions',
      ($9.Event value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Event.fromBuffer(value));
  static final _$getSyncSources = $grpc.ClientMethod<$4.User, $10.GetSyncSourcesResponse>(
      '/rellm.Rellm/GetSyncSources',
      ($4.User value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.GetSyncSourcesResponse.fromBuffer(value));
  static final _$createSyncSource = $grpc.ClientMethod<$10.SyncSource, $10.SyncSource>(
      '/rellm.Rellm/CreateSyncSource',
      ($10.SyncSource value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.SyncSource.fromBuffer(value));
  static final _$updateSyncSource = $grpc.ClientMethod<$10.SyncSource, $10.SyncSource>(
      '/rellm.Rellm/UpdateSyncSource',
      ($10.SyncSource value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.SyncSource.fromBuffer(value));
  static final _$deleteSyncSource = $grpc.ClientMethod<$10.DeleteSyncSourceRequest, $0.Empty>(
      '/rellm.Rellm/DeleteSyncSource',
      ($10.DeleteSyncSourceRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getSyncDestinations = $grpc.ClientMethod<$4.User, $10.GetSyncDestinationsResponse>(
      '/rellm.Rellm/GetSyncDestinations',
      ($4.User value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.GetSyncDestinationsResponse.fromBuffer(value));
  static final _$createSyncDestination = $grpc.ClientMethod<$10.SyncDestination, $10.SyncDestination>(
      '/rellm.Rellm/CreateSyncDestination',
      ($10.SyncDestination value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.SyncDestination.fromBuffer(value));
  static final _$updateSyncDestination = $grpc.ClientMethod<$10.SyncDestination, $10.SyncDestination>(
      '/rellm.Rellm/UpdateSyncDestination',
      ($10.SyncDestination value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $10.SyncDestination.fromBuffer(value));
  static final _$deleteSyncDestination = $grpc.ClientMethod<$10.DeleteSyncDestinationRequest, $0.Empty>(
      '/rellm.Rellm/DeleteSyncDestination',
      ($10.DeleteSyncDestinationRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$syncOccasion = $grpc.ClientMethod<$9.SyncOccasionRequest, $9.Occasion>(
      '/rellm.Rellm/SyncOccasion',
      ($9.SyncOccasionRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.Occasion.fromBuffer(value));
  static final _$deleteOccasionSyncDestination = $grpc.ClientMethod<$9.DeleteOccasionSyncDestinationRequest, $0.Empty>(
      '/rellm.Rellm/DeleteOccasionSyncDestination',
      ($9.DeleteOccasionSyncDestinationRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$getAIProviders = $grpc.ClientMethod<$4.User, $11.GetAIProvidersResponse>(
      '/rellm.Rellm/GetAIProviders',
      ($4.User value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $11.GetAIProvidersResponse.fromBuffer(value));
  static final _$createAIProvider = $grpc.ClientMethod<$11.AIProvider, $11.AIProvider>(
      '/rellm.Rellm/CreateAIProvider',
      ($11.AIProvider value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $11.AIProvider.fromBuffer(value));
  static final _$updateAIProvider = $grpc.ClientMethod<$11.AIProvider, $11.AIProvider>(
      '/rellm.Rellm/UpdateAIProvider',
      ($11.AIProvider value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $11.AIProvider.fromBuffer(value));
  static final _$deleteAIProvider = $grpc.ClientMethod<$11.DeleteAIProviderRequest, $0.Empty>(
      '/rellm.Rellm/DeleteAIProvider',
      ($11.DeleteAIProviderRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$grantAIProvider = $grpc.ClientMethod<$11.GrantAIProviderRequest, $11.AIProviderGrant>(
      '/rellm.Rellm/GrantAIProvider',
      ($11.GrantAIProviderRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $11.AIProviderGrant.fromBuffer(value));
  static final _$revokeAIProvider = $grpc.ClientMethod<$11.RevokeAIProviderRequest, $0.Empty>(
      '/rellm.Rellm/RevokeAIProvider',
      ($11.RevokeAIProviderRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$generateMedia = $grpc.ClientMethod<$11.GenerateMediaRequest, $5.Media>(
      '/rellm.Rellm/GenerateMedia',
      ($11.GenerateMediaRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $5.Media.fromBuffer(value));
  static final _$getEventAttendances = $grpc.ClientMethod<$9.GetEventAttendancesRequest, $9.EventAttendances>(
      '/rellm.Rellm/GetEventAttendances',
      ($9.GetEventAttendancesRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.EventAttendances.fromBuffer(value));
  static final _$upsertEventAttendance = $grpc.ClientMethod<$9.EventAttendance, $9.EventAttendance>(
      '/rellm.Rellm/UpsertEventAttendance',
      ($9.EventAttendance value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $9.EventAttendance.fromBuffer(value));
  static final _$deleteEventAttendance = $grpc.ClientMethod<$9.EventAttendance, $0.Empty>(
      '/rellm.Rellm/DeleteEventAttendance',
      ($9.EventAttendance value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$federateProfile = $grpc.ClientMethod<$1.FederatedAccount, $1.FederatedAccount>(
      '/rellm.Rellm/FederateProfile',
      ($1.FederatedAccount value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.FederatedAccount.fromBuffer(value));
  static final _$defederateProfile = $grpc.ClientMethod<$1.FederatedAccount, $0.Empty>(
      '/rellm.Rellm/DefederateProfile',
      ($1.FederatedAccount value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$configureServer = $grpc.ClientMethod<$2.ServerConfiguration, $2.ServerConfiguration>(
      '/rellm.Rellm/ConfigureServer',
      ($2.ServerConfiguration value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.ServerConfiguration.fromBuffer(value));
  static final _$lockClusterResources = $grpc.ClientMethod<$2.LockClusterResourcesRequest, $2.LockClusterResourcesResponse>(
      '/rellm.Rellm/LockClusterResources',
      ($2.LockClusterResourcesRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.LockClusterResourcesResponse.fromBuffer(value));
  static final _$freeClusterResources = $grpc.ClientMethod<$2.FreeClusterResourcesRequest, $0.Empty>(
      '/rellm.Rellm/FreeClusterResources',
      ($2.FreeClusterResourcesRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$resetData = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/rellm.Rellm/ResetData',
      ($0.Empty value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $0.Empty.fromBuffer(value));
  static final _$streamReplies = $grpc.ClientMethod<$8.Post, $8.Post>(
      '/rellm.Rellm/StreamReplies',
      ($8.Post value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $8.Post.fromBuffer(value));

  RellmClient($grpc.ClientChannel channel,
      {$grpc.CallOptions? options,
      $core.Iterable<$grpc.ClientInterceptor>? interceptors})
      : super(channel, options: options,
        interceptors: interceptors);

  $grpc.ResponseFuture<$1.GetServiceVersionResponse> getServiceVersion($0.Empty request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getServiceVersion, request, options: options);
  }

  $grpc.ResponseFuture<$2.ServerConfiguration> getServerConfiguration($0.Empty request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getServerConfiguration, request, options: options);
  }

  $grpc.ResponseFuture<$3.RefreshTokenResponse> createAccount($3.CreateAccountRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createAccount, request, options: options);
  }

  $grpc.ResponseFuture<$3.RefreshTokenResponse> login($3.LoginRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$login, request, options: options);
  }

  $grpc.ResponseFuture<$3.AccessTokenResponse> accessToken($3.AccessTokenRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$accessToken, request, options: options);
  }

  $grpc.ResponseFuture<$4.User> getCurrentUser($0.Empty request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getCurrentUser, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> resetPassword($3.ResetPasswordRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$resetPassword, request, options: options);
  }

  $grpc.ResponseFuture<$5.GetMediaResponse> getMedia($5.GetMediaRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getMedia, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteMedia($5.Media request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteMedia, request, options: options);
  }

  $grpc.ResponseFuture<$5.Media> updateMedia($5.Media request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateMedia, request, options: options);
  }

  $grpc.ResponseFuture<$5.Media> deleteMediaSizes($5.Media request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteMediaSizes, request, options: options);
  }

  $grpc.ResponseFuture<$4.GetUsersResponse> getUsers($4.GetUsersRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getUsers, request, options: options);
  }

  $grpc.ResponseFuture<$4.User> updateUser($4.User request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateUser, request, options: options);
  }

  $grpc.ResponseFuture<$4.ContactMethod> startContactMethodVerification($4.ContactMethod request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$startContactMethodVerification, request, options: options);
  }

  $grpc.ResponseFuture<$4.ContactMethod> verifyContactMethod($4.VerifyContactMethodRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$verifyContactMethod, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteUser($4.User request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteUser, request, options: options);
  }

  $grpc.ResponseFuture<$6.Message> sendMessage($6.SendMessageRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$sendMessage, request, options: options);
  }

  $grpc.ResponseFuture<$6.GetMessagesResponse> getMessages($6.GetMessagesRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getMessages, request, options: options);
  }

  $grpc.ResponseFuture<$6.MarkMessagesReadResponse> markMessagesRead($6.MarkMessagesReadRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$markMessagesRead, request, options: options);
  }

  $grpc.ResponseFuture<$6.PushSubscription> registerPushSubscription($6.RegisterPushSubscriptionRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$registerPushSubscription, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> unregisterPushSubscription($6.UnregisterPushSubscriptionRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$unregisterPushSubscription, request, options: options);
  }

  $grpc.ResponseFuture<$6.GetPushSubscriptionStatusResponse> getPushSubscriptionStatus($6.GetPushSubscriptionStatusRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getPushSubscriptionStatus, request, options: options);
  }

  $grpc.ResponseFuture<$4.Follow> createFollow($4.Follow request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createFollow, request, options: options);
  }

  $grpc.ResponseFuture<$4.Follow> updateFollow($4.Follow request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateFollow, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteFollow($4.Follow request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteFollow, request, options: options);
  }

  $grpc.ResponseFuture<$7.GetGroupsResponse> getGroups($7.GetGroupsRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getGroups, request, options: options);
  }

  $grpc.ResponseFuture<$7.Group> createGroup($7.Group request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createGroup, request, options: options);
  }

  $grpc.ResponseFuture<$7.Group> updateGroup($7.Group request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateGroup, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteGroup($7.Group request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteGroup, request, options: options);
  }

  $grpc.ResponseFuture<$7.GetMembersResponse> getMembers($7.GetMembersRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getMembers, request, options: options);
  }

  $grpc.ResponseFuture<$4.Membership> createMembership($4.Membership request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createMembership, request, options: options);
  }

  $grpc.ResponseFuture<$4.Membership> updateMembership($4.Membership request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateMembership, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteMembership($4.Membership request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteMembership, request, options: options);
  }

  $grpc.ResponseFuture<$8.GetPostsResponse> getPosts($8.GetPostsRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getPosts, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> createPost($8.Post request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createPost, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> updatePost($8.Post request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updatePost, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> deletePost($8.Post request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deletePost, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> starPost($8.Post request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$starPost, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> unstarPost($8.Post request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$unstarPost, request, options: options);
  }

  $grpc.ResponseFuture<$8.Post> syncPost($8.SyncPostRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$syncPost, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deletePostSyncDestination($8.DeletePostSyncDestinationRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deletePostSyncDestination, request, options: options);
  }

  $grpc.ResponseFuture<$8.GetGroupPostsResponse> getGroupPosts($8.GetGroupPostsRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getGroupPosts, request, options: options);
  }

  $grpc.ResponseFuture<$8.GroupPost> createGroupPost($8.GroupPost request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createGroupPost, request, options: options);
  }

  $grpc.ResponseFuture<$8.GroupPost> updateGroupPost($8.GroupPost request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateGroupPost, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteGroupPost($8.GroupPost request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteGroupPost, request, options: options);
  }

  $grpc.ResponseFuture<$9.GetEventsResponse> getEvents($9.GetEventsRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getEvents, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> createEvent($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createEvent, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> updateEvent($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateEvent, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> deleteEvent($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteEvent, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> updateEventDetails($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateEventDetails, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> createNewOccasions($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createNewOccasions, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> updateOccasions($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateOccasions, request, options: options);
  }

  $grpc.ResponseFuture<$9.Event> deleteRemovedOccasions($9.Event request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteRemovedOccasions, request, options: options);
  }

  $grpc.ResponseFuture<$10.GetSyncSourcesResponse> getSyncSources($4.User request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getSyncSources, request, options: options);
  }

  $grpc.ResponseFuture<$10.SyncSource> createSyncSource($10.SyncSource request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createSyncSource, request, options: options);
  }

  $grpc.ResponseFuture<$10.SyncSource> updateSyncSource($10.SyncSource request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateSyncSource, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteSyncSource($10.DeleteSyncSourceRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteSyncSource, request, options: options);
  }

  $grpc.ResponseFuture<$10.GetSyncDestinationsResponse> getSyncDestinations($4.User request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getSyncDestinations, request, options: options);
  }

  $grpc.ResponseFuture<$10.SyncDestination> createSyncDestination($10.SyncDestination request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createSyncDestination, request, options: options);
  }

  $grpc.ResponseFuture<$10.SyncDestination> updateSyncDestination($10.SyncDestination request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateSyncDestination, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteSyncDestination($10.DeleteSyncDestinationRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteSyncDestination, request, options: options);
  }

  $grpc.ResponseFuture<$9.Occasion> syncOccasion($9.SyncOccasionRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$syncOccasion, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteOccasionSyncDestination($9.DeleteOccasionSyncDestinationRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteOccasionSyncDestination, request, options: options);
  }

  $grpc.ResponseFuture<$11.GetAIProvidersResponse> getAIProviders($4.User request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getAIProviders, request, options: options);
  }

  $grpc.ResponseFuture<$11.AIProvider> createAIProvider($11.AIProvider request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$createAIProvider, request, options: options);
  }

  $grpc.ResponseFuture<$11.AIProvider> updateAIProvider($11.AIProvider request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$updateAIProvider, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteAIProvider($11.DeleteAIProviderRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteAIProvider, request, options: options);
  }

  $grpc.ResponseFuture<$11.AIProviderGrant> grantAIProvider($11.GrantAIProviderRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$grantAIProvider, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> revokeAIProvider($11.RevokeAIProviderRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$revokeAIProvider, request, options: options);
  }

  $grpc.ResponseFuture<$5.Media> generateMedia($11.GenerateMediaRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$generateMedia, request, options: options);
  }

  $grpc.ResponseFuture<$9.EventAttendances> getEventAttendances($9.GetEventAttendancesRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$getEventAttendances, request, options: options);
  }

  $grpc.ResponseFuture<$9.EventAttendance> upsertEventAttendance($9.EventAttendance request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$upsertEventAttendance, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> deleteEventAttendance($9.EventAttendance request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$deleteEventAttendance, request, options: options);
  }

  $grpc.ResponseFuture<$1.FederatedAccount> federateProfile($1.FederatedAccount request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$federateProfile, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> defederateProfile($1.FederatedAccount request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$defederateProfile, request, options: options);
  }

  $grpc.ResponseFuture<$2.ServerConfiguration> configureServer($2.ServerConfiguration request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$configureServer, request, options: options);
  }

  $grpc.ResponseFuture<$2.LockClusterResourcesResponse> lockClusterResources($2.LockClusterResourcesRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$lockClusterResources, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> freeClusterResources($2.FreeClusterResourcesRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$freeClusterResources, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> resetData($0.Empty request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$resetData, request, options: options);
  }

  $grpc.ResponseStream<$8.Post> streamReplies($8.Post request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$streamReplies, $async.Stream.fromIterable([request]), options: options);
  }
}

@$pb.GrpcServiceName('rellm.Rellm')
abstract class RellmServiceBase extends $grpc.Service {
  $core.String get $name => 'rellm.Rellm';

  RellmServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.GetServiceVersionResponse>(
        'GetServiceVersion',
        getServiceVersion_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.GetServiceVersionResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.ServerConfiguration>(
        'GetServerConfiguration',
        getServerConfiguration_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.ServerConfiguration value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$3.CreateAccountRequest, $3.RefreshTokenResponse>(
        'CreateAccount',
        createAccount_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $3.CreateAccountRequest.fromBuffer(value),
        ($3.RefreshTokenResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$3.LoginRequest, $3.RefreshTokenResponse>(
        'Login',
        login_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $3.LoginRequest.fromBuffer(value),
        ($3.RefreshTokenResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$3.AccessTokenRequest, $3.AccessTokenResponse>(
        'AccessToken',
        accessToken_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $3.AccessTokenRequest.fromBuffer(value),
        ($3.AccessTokenResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $4.User>(
        'GetCurrentUser',
        getCurrentUser_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($4.User value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$3.ResetPasswordRequest, $0.Empty>(
        'ResetPassword',
        resetPassword_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $3.ResetPasswordRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$5.GetMediaRequest, $5.GetMediaResponse>(
        'GetMedia',
        getMedia_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $5.GetMediaRequest.fromBuffer(value),
        ($5.GetMediaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$5.Media, $0.Empty>(
        'DeleteMedia',
        deleteMedia_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $5.Media.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$5.Media, $5.Media>(
        'UpdateMedia',
        updateMedia_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $5.Media.fromBuffer(value),
        ($5.Media value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$5.Media, $5.Media>(
        'DeleteMediaSizes',
        deleteMediaSizes_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $5.Media.fromBuffer(value),
        ($5.Media value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.GetUsersRequest, $4.GetUsersResponse>(
        'GetUsers',
        getUsers_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.GetUsersRequest.fromBuffer(value),
        ($4.GetUsersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.User, $4.User>(
        'UpdateUser',
        updateUser_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.User.fromBuffer(value),
        ($4.User value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.ContactMethod, $4.ContactMethod>(
        'StartContactMethodVerification',
        startContactMethodVerification_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.ContactMethod.fromBuffer(value),
        ($4.ContactMethod value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.VerifyContactMethodRequest, $4.ContactMethod>(
        'VerifyContactMethod',
        verifyContactMethod_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.VerifyContactMethodRequest.fromBuffer(value),
        ($4.ContactMethod value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.User, $0.Empty>(
        'DeleteUser',
        deleteUser_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.User.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.SendMessageRequest, $6.Message>(
        'SendMessage',
        sendMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.SendMessageRequest.fromBuffer(value),
        ($6.Message value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.GetMessagesRequest, $6.GetMessagesResponse>(
        'GetMessages',
        getMessages_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.GetMessagesRequest.fromBuffer(value),
        ($6.GetMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.MarkMessagesReadRequest, $6.MarkMessagesReadResponse>(
        'MarkMessagesRead',
        markMessagesRead_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.MarkMessagesReadRequest.fromBuffer(value),
        ($6.MarkMessagesReadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.RegisterPushSubscriptionRequest, $6.PushSubscription>(
        'RegisterPushSubscription',
        registerPushSubscription_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.RegisterPushSubscriptionRequest.fromBuffer(value),
        ($6.PushSubscription value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.UnregisterPushSubscriptionRequest, $0.Empty>(
        'UnregisterPushSubscription',
        unregisterPushSubscription_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.UnregisterPushSubscriptionRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$6.GetPushSubscriptionStatusRequest, $6.GetPushSubscriptionStatusResponse>(
        'GetPushSubscriptionStatus',
        getPushSubscriptionStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $6.GetPushSubscriptionStatusRequest.fromBuffer(value),
        ($6.GetPushSubscriptionStatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Follow, $4.Follow>(
        'CreateFollow',
        createFollow_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Follow.fromBuffer(value),
        ($4.Follow value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Follow, $4.Follow>(
        'UpdateFollow',
        updateFollow_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Follow.fromBuffer(value),
        ($4.Follow value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Follow, $0.Empty>(
        'DeleteFollow',
        deleteFollow_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Follow.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.GetGroupsRequest, $7.GetGroupsResponse>(
        'GetGroups',
        getGroups_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.GetGroupsRequest.fromBuffer(value),
        ($7.GetGroupsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.Group, $7.Group>(
        'CreateGroup',
        createGroup_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.Group.fromBuffer(value),
        ($7.Group value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.Group, $7.Group>(
        'UpdateGroup',
        updateGroup_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.Group.fromBuffer(value),
        ($7.Group value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.Group, $0.Empty>(
        'DeleteGroup',
        deleteGroup_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.Group.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$7.GetMembersRequest, $7.GetMembersResponse>(
        'GetMembers',
        getMembers_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $7.GetMembersRequest.fromBuffer(value),
        ($7.GetMembersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Membership, $4.Membership>(
        'CreateMembership',
        createMembership_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Membership.fromBuffer(value),
        ($4.Membership value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Membership, $4.Membership>(
        'UpdateMembership',
        updateMembership_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Membership.fromBuffer(value),
        ($4.Membership value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.Membership, $0.Empty>(
        'DeleteMembership',
        deleteMembership_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.Membership.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.GetPostsRequest, $8.GetPostsResponse>(
        'GetPosts',
        getPosts_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.GetPostsRequest.fromBuffer(value),
        ($8.GetPostsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'CreatePost',
        createPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'UpdatePost',
        updatePost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'DeletePost',
        deletePost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'StarPost',
        starPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'UnstarPost',
        unstarPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.SyncPostRequest, $8.Post>(
        'SyncPost',
        syncPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.SyncPostRequest.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.DeletePostSyncDestinationRequest, $0.Empty>(
        'DeletePostSyncDestination',
        deletePostSyncDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.DeletePostSyncDestinationRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.GetGroupPostsRequest, $8.GetGroupPostsResponse>(
        'GetGroupPosts',
        getGroupPosts_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.GetGroupPostsRequest.fromBuffer(value),
        ($8.GetGroupPostsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.GroupPost, $8.GroupPost>(
        'CreateGroupPost',
        createGroupPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.GroupPost.fromBuffer(value),
        ($8.GroupPost value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.GroupPost, $8.GroupPost>(
        'UpdateGroupPost',
        updateGroupPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.GroupPost.fromBuffer(value),
        ($8.GroupPost value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.GroupPost, $0.Empty>(
        'DeleteGroupPost',
        deleteGroupPost_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $8.GroupPost.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.GetEventsRequest, $9.GetEventsResponse>(
        'GetEvents',
        getEvents_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.GetEventsRequest.fromBuffer(value),
        ($9.GetEventsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'CreateEvent',
        createEvent_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'UpdateEvent',
        updateEvent_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'DeleteEvent',
        deleteEvent_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'UpdateEventDetails',
        updateEventDetails_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'CreateNewOccasions',
        createNewOccasions_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'UpdateOccasions',
        updateOccasions_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.Event, $9.Event>(
        'DeleteRemovedOccasions',
        deleteRemovedOccasions_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.Event.fromBuffer(value),
        ($9.Event value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.User, $10.GetSyncSourcesResponse>(
        'GetSyncSources',
        getSyncSources_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.User.fromBuffer(value),
        ($10.GetSyncSourcesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.SyncSource, $10.SyncSource>(
        'CreateSyncSource',
        createSyncSource_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.SyncSource.fromBuffer(value),
        ($10.SyncSource value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.SyncSource, $10.SyncSource>(
        'UpdateSyncSource',
        updateSyncSource_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.SyncSource.fromBuffer(value),
        ($10.SyncSource value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.DeleteSyncSourceRequest, $0.Empty>(
        'DeleteSyncSource',
        deleteSyncSource_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.DeleteSyncSourceRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.User, $10.GetSyncDestinationsResponse>(
        'GetSyncDestinations',
        getSyncDestinations_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.User.fromBuffer(value),
        ($10.GetSyncDestinationsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.SyncDestination, $10.SyncDestination>(
        'CreateSyncDestination',
        createSyncDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.SyncDestination.fromBuffer(value),
        ($10.SyncDestination value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.SyncDestination, $10.SyncDestination>(
        'UpdateSyncDestination',
        updateSyncDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.SyncDestination.fromBuffer(value),
        ($10.SyncDestination value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$10.DeleteSyncDestinationRequest, $0.Empty>(
        'DeleteSyncDestination',
        deleteSyncDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $10.DeleteSyncDestinationRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.SyncOccasionRequest, $9.Occasion>(
        'SyncOccasion',
        syncOccasion_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.SyncOccasionRequest.fromBuffer(value),
        ($9.Occasion value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.DeleteOccasionSyncDestinationRequest, $0.Empty>(
        'DeleteOccasionSyncDestination',
        deleteOccasionSyncDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.DeleteOccasionSyncDestinationRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$4.User, $11.GetAIProvidersResponse>(
        'GetAIProviders',
        getAIProviders_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $4.User.fromBuffer(value),
        ($11.GetAIProvidersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.AIProvider, $11.AIProvider>(
        'CreateAIProvider',
        createAIProvider_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.AIProvider.fromBuffer(value),
        ($11.AIProvider value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.AIProvider, $11.AIProvider>(
        'UpdateAIProvider',
        updateAIProvider_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.AIProvider.fromBuffer(value),
        ($11.AIProvider value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.DeleteAIProviderRequest, $0.Empty>(
        'DeleteAIProvider',
        deleteAIProvider_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.DeleteAIProviderRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.GrantAIProviderRequest, $11.AIProviderGrant>(
        'GrantAIProvider',
        grantAIProvider_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.GrantAIProviderRequest.fromBuffer(value),
        ($11.AIProviderGrant value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.RevokeAIProviderRequest, $0.Empty>(
        'RevokeAIProvider',
        revokeAIProvider_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.RevokeAIProviderRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$11.GenerateMediaRequest, $5.Media>(
        'GenerateMedia',
        generateMedia_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $11.GenerateMediaRequest.fromBuffer(value),
        ($5.Media value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.GetEventAttendancesRequest, $9.EventAttendances>(
        'GetEventAttendances',
        getEventAttendances_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.GetEventAttendancesRequest.fromBuffer(value),
        ($9.EventAttendances value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.EventAttendance, $9.EventAttendance>(
        'UpsertEventAttendance',
        upsertEventAttendance_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.EventAttendance.fromBuffer(value),
        ($9.EventAttendance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$9.EventAttendance, $0.Empty>(
        'DeleteEventAttendance',
        deleteEventAttendance_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $9.EventAttendance.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.FederatedAccount, $1.FederatedAccount>(
        'FederateProfile',
        federateProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.FederatedAccount.fromBuffer(value),
        ($1.FederatedAccount value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.FederatedAccount, $0.Empty>(
        'DefederateProfile',
        defederateProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.FederatedAccount.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$2.ServerConfiguration, $2.ServerConfiguration>(
        'ConfigureServer',
        configureServer_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $2.ServerConfiguration.fromBuffer(value),
        ($2.ServerConfiguration value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$2.LockClusterResourcesRequest, $2.LockClusterResourcesResponse>(
        'LockClusterResources',
        lockClusterResources_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $2.LockClusterResourcesRequest.fromBuffer(value),
        ($2.LockClusterResourcesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$2.FreeClusterResourcesRequest, $0.Empty>(
        'FreeClusterResources',
        freeClusterResources_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $2.FreeClusterResourcesRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'ResetData',
        resetData_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$8.Post, $8.Post>(
        'StreamReplies',
        streamReplies_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $8.Post.fromBuffer(value),
        ($8.Post value) => value.writeToBuffer()));
  }

  $async.Future<$1.GetServiceVersionResponse> getServiceVersion_Pre($grpc.ServiceCall call, $async.Future<$0.Empty> request) async {
    return getServiceVersion(call, await request);
  }

  $async.Future<$2.ServerConfiguration> getServerConfiguration_Pre($grpc.ServiceCall call, $async.Future<$0.Empty> request) async {
    return getServerConfiguration(call, await request);
  }

  $async.Future<$3.RefreshTokenResponse> createAccount_Pre($grpc.ServiceCall call, $async.Future<$3.CreateAccountRequest> request) async {
    return createAccount(call, await request);
  }

  $async.Future<$3.RefreshTokenResponse> login_Pre($grpc.ServiceCall call, $async.Future<$3.LoginRequest> request) async {
    return login(call, await request);
  }

  $async.Future<$3.AccessTokenResponse> accessToken_Pre($grpc.ServiceCall call, $async.Future<$3.AccessTokenRequest> request) async {
    return accessToken(call, await request);
  }

  $async.Future<$4.User> getCurrentUser_Pre($grpc.ServiceCall call, $async.Future<$0.Empty> request) async {
    return getCurrentUser(call, await request);
  }

  $async.Future<$0.Empty> resetPassword_Pre($grpc.ServiceCall call, $async.Future<$3.ResetPasswordRequest> request) async {
    return resetPassword(call, await request);
  }

  $async.Future<$5.GetMediaResponse> getMedia_Pre($grpc.ServiceCall call, $async.Future<$5.GetMediaRequest> request) async {
    return getMedia(call, await request);
  }

  $async.Future<$0.Empty> deleteMedia_Pre($grpc.ServiceCall call, $async.Future<$5.Media> request) async {
    return deleteMedia(call, await request);
  }

  $async.Future<$5.Media> updateMedia_Pre($grpc.ServiceCall call, $async.Future<$5.Media> request) async {
    return updateMedia(call, await request);
  }

  $async.Future<$5.Media> deleteMediaSizes_Pre($grpc.ServiceCall call, $async.Future<$5.Media> request) async {
    return deleteMediaSizes(call, await request);
  }

  $async.Future<$4.GetUsersResponse> getUsers_Pre($grpc.ServiceCall call, $async.Future<$4.GetUsersRequest> request) async {
    return getUsers(call, await request);
  }

  $async.Future<$4.User> updateUser_Pre($grpc.ServiceCall call, $async.Future<$4.User> request) async {
    return updateUser(call, await request);
  }

  $async.Future<$4.ContactMethod> startContactMethodVerification_Pre($grpc.ServiceCall call, $async.Future<$4.ContactMethod> request) async {
    return startContactMethodVerification(call, await request);
  }

  $async.Future<$4.ContactMethod> verifyContactMethod_Pre($grpc.ServiceCall call, $async.Future<$4.VerifyContactMethodRequest> request) async {
    return verifyContactMethod(call, await request);
  }

  $async.Future<$0.Empty> deleteUser_Pre($grpc.ServiceCall call, $async.Future<$4.User> request) async {
    return deleteUser(call, await request);
  }

  $async.Future<$6.Message> sendMessage_Pre($grpc.ServiceCall call, $async.Future<$6.SendMessageRequest> request) async {
    return sendMessage(call, await request);
  }

  $async.Future<$6.GetMessagesResponse> getMessages_Pre($grpc.ServiceCall call, $async.Future<$6.GetMessagesRequest> request) async {
    return getMessages(call, await request);
  }

  $async.Future<$6.MarkMessagesReadResponse> markMessagesRead_Pre($grpc.ServiceCall call, $async.Future<$6.MarkMessagesReadRequest> request) async {
    return markMessagesRead(call, await request);
  }

  $async.Future<$6.PushSubscription> registerPushSubscription_Pre($grpc.ServiceCall call, $async.Future<$6.RegisterPushSubscriptionRequest> request) async {
    return registerPushSubscription(call, await request);
  }

  $async.Future<$0.Empty> unregisterPushSubscription_Pre($grpc.ServiceCall call, $async.Future<$6.UnregisterPushSubscriptionRequest> request) async {
    return unregisterPushSubscription(call, await request);
  }

  $async.Future<$6.GetPushSubscriptionStatusResponse> getPushSubscriptionStatus_Pre($grpc.ServiceCall call, $async.Future<$6.GetPushSubscriptionStatusRequest> request) async {
    return getPushSubscriptionStatus(call, await request);
  }

  $async.Future<$4.Follow> createFollow_Pre($grpc.ServiceCall call, $async.Future<$4.Follow> request) async {
    return createFollow(call, await request);
  }

  $async.Future<$4.Follow> updateFollow_Pre($grpc.ServiceCall call, $async.Future<$4.Follow> request) async {
    return updateFollow(call, await request);
  }

  $async.Future<$0.Empty> deleteFollow_Pre($grpc.ServiceCall call, $async.Future<$4.Follow> request) async {
    return deleteFollow(call, await request);
  }

  $async.Future<$7.GetGroupsResponse> getGroups_Pre($grpc.ServiceCall call, $async.Future<$7.GetGroupsRequest> request) async {
    return getGroups(call, await request);
  }

  $async.Future<$7.Group> createGroup_Pre($grpc.ServiceCall call, $async.Future<$7.Group> request) async {
    return createGroup(call, await request);
  }

  $async.Future<$7.Group> updateGroup_Pre($grpc.ServiceCall call, $async.Future<$7.Group> request) async {
    return updateGroup(call, await request);
  }

  $async.Future<$0.Empty> deleteGroup_Pre($grpc.ServiceCall call, $async.Future<$7.Group> request) async {
    return deleteGroup(call, await request);
  }

  $async.Future<$7.GetMembersResponse> getMembers_Pre($grpc.ServiceCall call, $async.Future<$7.GetMembersRequest> request) async {
    return getMembers(call, await request);
  }

  $async.Future<$4.Membership> createMembership_Pre($grpc.ServiceCall call, $async.Future<$4.Membership> request) async {
    return createMembership(call, await request);
  }

  $async.Future<$4.Membership> updateMembership_Pre($grpc.ServiceCall call, $async.Future<$4.Membership> request) async {
    return updateMembership(call, await request);
  }

  $async.Future<$0.Empty> deleteMembership_Pre($grpc.ServiceCall call, $async.Future<$4.Membership> request) async {
    return deleteMembership(call, await request);
  }

  $async.Future<$8.GetPostsResponse> getPosts_Pre($grpc.ServiceCall call, $async.Future<$8.GetPostsRequest> request) async {
    return getPosts(call, await request);
  }

  $async.Future<$8.Post> createPost_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async {
    return createPost(call, await request);
  }

  $async.Future<$8.Post> updatePost_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async {
    return updatePost(call, await request);
  }

  $async.Future<$8.Post> deletePost_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async {
    return deletePost(call, await request);
  }

  $async.Future<$8.Post> starPost_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async {
    return starPost(call, await request);
  }

  $async.Future<$8.Post> unstarPost_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async {
    return unstarPost(call, await request);
  }

  $async.Future<$8.Post> syncPost_Pre($grpc.ServiceCall call, $async.Future<$8.SyncPostRequest> request) async {
    return syncPost(call, await request);
  }

  $async.Future<$0.Empty> deletePostSyncDestination_Pre($grpc.ServiceCall call, $async.Future<$8.DeletePostSyncDestinationRequest> request) async {
    return deletePostSyncDestination(call, await request);
  }

  $async.Future<$8.GetGroupPostsResponse> getGroupPosts_Pre($grpc.ServiceCall call, $async.Future<$8.GetGroupPostsRequest> request) async {
    return getGroupPosts(call, await request);
  }

  $async.Future<$8.GroupPost> createGroupPost_Pre($grpc.ServiceCall call, $async.Future<$8.GroupPost> request) async {
    return createGroupPost(call, await request);
  }

  $async.Future<$8.GroupPost> updateGroupPost_Pre($grpc.ServiceCall call, $async.Future<$8.GroupPost> request) async {
    return updateGroupPost(call, await request);
  }

  $async.Future<$0.Empty> deleteGroupPost_Pre($grpc.ServiceCall call, $async.Future<$8.GroupPost> request) async {
    return deleteGroupPost(call, await request);
  }

  $async.Future<$9.GetEventsResponse> getEvents_Pre($grpc.ServiceCall call, $async.Future<$9.GetEventsRequest> request) async {
    return getEvents(call, await request);
  }

  $async.Future<$9.Event> createEvent_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return createEvent(call, await request);
  }

  $async.Future<$9.Event> updateEvent_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return updateEvent(call, await request);
  }

  $async.Future<$9.Event> deleteEvent_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return deleteEvent(call, await request);
  }

  $async.Future<$9.Event> updateEventDetails_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return updateEventDetails(call, await request);
  }

  $async.Future<$9.Event> createNewOccasions_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return createNewOccasions(call, await request);
  }

  $async.Future<$9.Event> updateOccasions_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return updateOccasions(call, await request);
  }

  $async.Future<$9.Event> deleteRemovedOccasions_Pre($grpc.ServiceCall call, $async.Future<$9.Event> request) async {
    return deleteRemovedOccasions(call, await request);
  }

  $async.Future<$10.GetSyncSourcesResponse> getSyncSources_Pre($grpc.ServiceCall call, $async.Future<$4.User> request) async {
    return getSyncSources(call, await request);
  }

  $async.Future<$10.SyncSource> createSyncSource_Pre($grpc.ServiceCall call, $async.Future<$10.SyncSource> request) async {
    return createSyncSource(call, await request);
  }

  $async.Future<$10.SyncSource> updateSyncSource_Pre($grpc.ServiceCall call, $async.Future<$10.SyncSource> request) async {
    return updateSyncSource(call, await request);
  }

  $async.Future<$0.Empty> deleteSyncSource_Pre($grpc.ServiceCall call, $async.Future<$10.DeleteSyncSourceRequest> request) async {
    return deleteSyncSource(call, await request);
  }

  $async.Future<$10.GetSyncDestinationsResponse> getSyncDestinations_Pre($grpc.ServiceCall call, $async.Future<$4.User> request) async {
    return getSyncDestinations(call, await request);
  }

  $async.Future<$10.SyncDestination> createSyncDestination_Pre($grpc.ServiceCall call, $async.Future<$10.SyncDestination> request) async {
    return createSyncDestination(call, await request);
  }

  $async.Future<$10.SyncDestination> updateSyncDestination_Pre($grpc.ServiceCall call, $async.Future<$10.SyncDestination> request) async {
    return updateSyncDestination(call, await request);
  }

  $async.Future<$0.Empty> deleteSyncDestination_Pre($grpc.ServiceCall call, $async.Future<$10.DeleteSyncDestinationRequest> request) async {
    return deleteSyncDestination(call, await request);
  }

  $async.Future<$9.Occasion> syncOccasion_Pre($grpc.ServiceCall call, $async.Future<$9.SyncOccasionRequest> request) async {
    return syncOccasion(call, await request);
  }

  $async.Future<$0.Empty> deleteOccasionSyncDestination_Pre($grpc.ServiceCall call, $async.Future<$9.DeleteOccasionSyncDestinationRequest> request) async {
    return deleteOccasionSyncDestination(call, await request);
  }

  $async.Future<$11.GetAIProvidersResponse> getAIProviders_Pre($grpc.ServiceCall call, $async.Future<$4.User> request) async {
    return getAIProviders(call, await request);
  }

  $async.Future<$11.AIProvider> createAIProvider_Pre($grpc.ServiceCall call, $async.Future<$11.AIProvider> request) async {
    return createAIProvider(call, await request);
  }

  $async.Future<$11.AIProvider> updateAIProvider_Pre($grpc.ServiceCall call, $async.Future<$11.AIProvider> request) async {
    return updateAIProvider(call, await request);
  }

  $async.Future<$0.Empty> deleteAIProvider_Pre($grpc.ServiceCall call, $async.Future<$11.DeleteAIProviderRequest> request) async {
    return deleteAIProvider(call, await request);
  }

  $async.Future<$11.AIProviderGrant> grantAIProvider_Pre($grpc.ServiceCall call, $async.Future<$11.GrantAIProviderRequest> request) async {
    return grantAIProvider(call, await request);
  }

  $async.Future<$0.Empty> revokeAIProvider_Pre($grpc.ServiceCall call, $async.Future<$11.RevokeAIProviderRequest> request) async {
    return revokeAIProvider(call, await request);
  }

  $async.Future<$5.Media> generateMedia_Pre($grpc.ServiceCall call, $async.Future<$11.GenerateMediaRequest> request) async {
    return generateMedia(call, await request);
  }

  $async.Future<$9.EventAttendances> getEventAttendances_Pre($grpc.ServiceCall call, $async.Future<$9.GetEventAttendancesRequest> request) async {
    return getEventAttendances(call, await request);
  }

  $async.Future<$9.EventAttendance> upsertEventAttendance_Pre($grpc.ServiceCall call, $async.Future<$9.EventAttendance> request) async {
    return upsertEventAttendance(call, await request);
  }

  $async.Future<$0.Empty> deleteEventAttendance_Pre($grpc.ServiceCall call, $async.Future<$9.EventAttendance> request) async {
    return deleteEventAttendance(call, await request);
  }

  $async.Future<$1.FederatedAccount> federateProfile_Pre($grpc.ServiceCall call, $async.Future<$1.FederatedAccount> request) async {
    return federateProfile(call, await request);
  }

  $async.Future<$0.Empty> defederateProfile_Pre($grpc.ServiceCall call, $async.Future<$1.FederatedAccount> request) async {
    return defederateProfile(call, await request);
  }

  $async.Future<$2.ServerConfiguration> configureServer_Pre($grpc.ServiceCall call, $async.Future<$2.ServerConfiguration> request) async {
    return configureServer(call, await request);
  }

  $async.Future<$2.LockClusterResourcesResponse> lockClusterResources_Pre($grpc.ServiceCall call, $async.Future<$2.LockClusterResourcesRequest> request) async {
    return lockClusterResources(call, await request);
  }

  $async.Future<$0.Empty> freeClusterResources_Pre($grpc.ServiceCall call, $async.Future<$2.FreeClusterResourcesRequest> request) async {
    return freeClusterResources(call, await request);
  }

  $async.Future<$0.Empty> resetData_Pre($grpc.ServiceCall call, $async.Future<$0.Empty> request) async {
    return resetData(call, await request);
  }

  $async.Stream<$8.Post> streamReplies_Pre($grpc.ServiceCall call, $async.Future<$8.Post> request) async* {
    yield* streamReplies(call, await request);
  }

  $async.Future<$1.GetServiceVersionResponse> getServiceVersion($grpc.ServiceCall call, $0.Empty request);
  $async.Future<$2.ServerConfiguration> getServerConfiguration($grpc.ServiceCall call, $0.Empty request);
  $async.Future<$3.RefreshTokenResponse> createAccount($grpc.ServiceCall call, $3.CreateAccountRequest request);
  $async.Future<$3.RefreshTokenResponse> login($grpc.ServiceCall call, $3.LoginRequest request);
  $async.Future<$3.AccessTokenResponse> accessToken($grpc.ServiceCall call, $3.AccessTokenRequest request);
  $async.Future<$4.User> getCurrentUser($grpc.ServiceCall call, $0.Empty request);
  $async.Future<$0.Empty> resetPassword($grpc.ServiceCall call, $3.ResetPasswordRequest request);
  $async.Future<$5.GetMediaResponse> getMedia($grpc.ServiceCall call, $5.GetMediaRequest request);
  $async.Future<$0.Empty> deleteMedia($grpc.ServiceCall call, $5.Media request);
  $async.Future<$5.Media> updateMedia($grpc.ServiceCall call, $5.Media request);
  $async.Future<$5.Media> deleteMediaSizes($grpc.ServiceCall call, $5.Media request);
  $async.Future<$4.GetUsersResponse> getUsers($grpc.ServiceCall call, $4.GetUsersRequest request);
  $async.Future<$4.User> updateUser($grpc.ServiceCall call, $4.User request);
  $async.Future<$4.ContactMethod> startContactMethodVerification($grpc.ServiceCall call, $4.ContactMethod request);
  $async.Future<$4.ContactMethod> verifyContactMethod($grpc.ServiceCall call, $4.VerifyContactMethodRequest request);
  $async.Future<$0.Empty> deleteUser($grpc.ServiceCall call, $4.User request);
  $async.Future<$6.Message> sendMessage($grpc.ServiceCall call, $6.SendMessageRequest request);
  $async.Future<$6.GetMessagesResponse> getMessages($grpc.ServiceCall call, $6.GetMessagesRequest request);
  $async.Future<$6.MarkMessagesReadResponse> markMessagesRead($grpc.ServiceCall call, $6.MarkMessagesReadRequest request);
  $async.Future<$6.PushSubscription> registerPushSubscription($grpc.ServiceCall call, $6.RegisterPushSubscriptionRequest request);
  $async.Future<$0.Empty> unregisterPushSubscription($grpc.ServiceCall call, $6.UnregisterPushSubscriptionRequest request);
  $async.Future<$6.GetPushSubscriptionStatusResponse> getPushSubscriptionStatus($grpc.ServiceCall call, $6.GetPushSubscriptionStatusRequest request);
  $async.Future<$4.Follow> createFollow($grpc.ServiceCall call, $4.Follow request);
  $async.Future<$4.Follow> updateFollow($grpc.ServiceCall call, $4.Follow request);
  $async.Future<$0.Empty> deleteFollow($grpc.ServiceCall call, $4.Follow request);
  $async.Future<$7.GetGroupsResponse> getGroups($grpc.ServiceCall call, $7.GetGroupsRequest request);
  $async.Future<$7.Group> createGroup($grpc.ServiceCall call, $7.Group request);
  $async.Future<$7.Group> updateGroup($grpc.ServiceCall call, $7.Group request);
  $async.Future<$0.Empty> deleteGroup($grpc.ServiceCall call, $7.Group request);
  $async.Future<$7.GetMembersResponse> getMembers($grpc.ServiceCall call, $7.GetMembersRequest request);
  $async.Future<$4.Membership> createMembership($grpc.ServiceCall call, $4.Membership request);
  $async.Future<$4.Membership> updateMembership($grpc.ServiceCall call, $4.Membership request);
  $async.Future<$0.Empty> deleteMembership($grpc.ServiceCall call, $4.Membership request);
  $async.Future<$8.GetPostsResponse> getPosts($grpc.ServiceCall call, $8.GetPostsRequest request);
  $async.Future<$8.Post> createPost($grpc.ServiceCall call, $8.Post request);
  $async.Future<$8.Post> updatePost($grpc.ServiceCall call, $8.Post request);
  $async.Future<$8.Post> deletePost($grpc.ServiceCall call, $8.Post request);
  $async.Future<$8.Post> starPost($grpc.ServiceCall call, $8.Post request);
  $async.Future<$8.Post> unstarPost($grpc.ServiceCall call, $8.Post request);
  $async.Future<$8.Post> syncPost($grpc.ServiceCall call, $8.SyncPostRequest request);
  $async.Future<$0.Empty> deletePostSyncDestination($grpc.ServiceCall call, $8.DeletePostSyncDestinationRequest request);
  $async.Future<$8.GetGroupPostsResponse> getGroupPosts($grpc.ServiceCall call, $8.GetGroupPostsRequest request);
  $async.Future<$8.GroupPost> createGroupPost($grpc.ServiceCall call, $8.GroupPost request);
  $async.Future<$8.GroupPost> updateGroupPost($grpc.ServiceCall call, $8.GroupPost request);
  $async.Future<$0.Empty> deleteGroupPost($grpc.ServiceCall call, $8.GroupPost request);
  $async.Future<$9.GetEventsResponse> getEvents($grpc.ServiceCall call, $9.GetEventsRequest request);
  $async.Future<$9.Event> createEvent($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> updateEvent($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> deleteEvent($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> updateEventDetails($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> createNewOccasions($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> updateOccasions($grpc.ServiceCall call, $9.Event request);
  $async.Future<$9.Event> deleteRemovedOccasions($grpc.ServiceCall call, $9.Event request);
  $async.Future<$10.GetSyncSourcesResponse> getSyncSources($grpc.ServiceCall call, $4.User request);
  $async.Future<$10.SyncSource> createSyncSource($grpc.ServiceCall call, $10.SyncSource request);
  $async.Future<$10.SyncSource> updateSyncSource($grpc.ServiceCall call, $10.SyncSource request);
  $async.Future<$0.Empty> deleteSyncSource($grpc.ServiceCall call, $10.DeleteSyncSourceRequest request);
  $async.Future<$10.GetSyncDestinationsResponse> getSyncDestinations($grpc.ServiceCall call, $4.User request);
  $async.Future<$10.SyncDestination> createSyncDestination($grpc.ServiceCall call, $10.SyncDestination request);
  $async.Future<$10.SyncDestination> updateSyncDestination($grpc.ServiceCall call, $10.SyncDestination request);
  $async.Future<$0.Empty> deleteSyncDestination($grpc.ServiceCall call, $10.DeleteSyncDestinationRequest request);
  $async.Future<$9.Occasion> syncOccasion($grpc.ServiceCall call, $9.SyncOccasionRequest request);
  $async.Future<$0.Empty> deleteOccasionSyncDestination($grpc.ServiceCall call, $9.DeleteOccasionSyncDestinationRequest request);
  $async.Future<$11.GetAIProvidersResponse> getAIProviders($grpc.ServiceCall call, $4.User request);
  $async.Future<$11.AIProvider> createAIProvider($grpc.ServiceCall call, $11.AIProvider request);
  $async.Future<$11.AIProvider> updateAIProvider($grpc.ServiceCall call, $11.AIProvider request);
  $async.Future<$0.Empty> deleteAIProvider($grpc.ServiceCall call, $11.DeleteAIProviderRequest request);
  $async.Future<$11.AIProviderGrant> grantAIProvider($grpc.ServiceCall call, $11.GrantAIProviderRequest request);
  $async.Future<$0.Empty> revokeAIProvider($grpc.ServiceCall call, $11.RevokeAIProviderRequest request);
  $async.Future<$5.Media> generateMedia($grpc.ServiceCall call, $11.GenerateMediaRequest request);
  $async.Future<$9.EventAttendances> getEventAttendances($grpc.ServiceCall call, $9.GetEventAttendancesRequest request);
  $async.Future<$9.EventAttendance> upsertEventAttendance($grpc.ServiceCall call, $9.EventAttendance request);
  $async.Future<$0.Empty> deleteEventAttendance($grpc.ServiceCall call, $9.EventAttendance request);
  $async.Future<$1.FederatedAccount> federateProfile($grpc.ServiceCall call, $1.FederatedAccount request);
  $async.Future<$0.Empty> defederateProfile($grpc.ServiceCall call, $1.FederatedAccount request);
  $async.Future<$2.ServerConfiguration> configureServer($grpc.ServiceCall call, $2.ServerConfiguration request);
  $async.Future<$2.LockClusterResourcesResponse> lockClusterResources($grpc.ServiceCall call, $2.LockClusterResourcesRequest request);
  $async.Future<$0.Empty> freeClusterResources($grpc.ServiceCall call, $2.FreeClusterResourcesRequest request);
  $async.Future<$0.Empty> resetData($grpc.ServiceCall call, $0.Empty request);
  $async.Stream<$8.Post> streamReplies($grpc.ServiceCall call, $8.Post request);
}
