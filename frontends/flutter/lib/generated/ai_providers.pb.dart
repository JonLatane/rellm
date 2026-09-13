//
//  Generated code. Do not modify.
//  source: ai_providers.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'ai_providers.pbenum.dart';
import 'google/protobuf/timestamp.pb.dart' as $12;
import 'media.pb.dart' as $5;

export 'ai_providers.pbenum.dart';

/// One specific model a user may call right now, and how - via an [`AIProvider`](#rellm-AIProvider)
/// they own outright (`grant` unset), or via an [`AIProviderGrant`](#rellm-AIProviderGrant) someone else
/// granted them (`grant` set). Only ever defined relative to a user - see
/// [`User.ai_models`](#rellm-User)/[`GetAIProvidersResponse.ai_models`](#rellm-GetAIProvidersResponse).
/// One `AIModel` exists per (provider, model) pair: an owner gets one row per model their
/// provider supports (see the server's own model catalog per provider type); a grantee gets one row
/// per model their grant actually covers - expanded from `AIProviderGrant.model_names`, or
/// every model the provider supports if that list is empty.
class AIModel extends $pb.GeneratedMessage {
  factory AIModel({
    $core.String? modelName,
    $core.Iterable<AIModelCapability>? capabilities,
    AIProviderGrant? grant,
    AIProvider? provider,
  }) {
    final $result = create();
    if (modelName != null) {
      $result.modelName = modelName;
    }
    if (capabilities != null) {
      $result.capabilities.addAll(capabilities);
    }
    if (grant != null) {
      $result.grant = grant;
    }
    if (provider != null) {
      $result.provider = provider;
    }
    return $result;
  }
  AIModel._() : super();
  factory AIModel.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIModel.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIModel', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelName')
    ..pc<AIModelCapability>(2, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.KE, valueOf: AIModelCapability.valueOf, enumValues: AIModelCapability.values, defaultEnumValue: AIModelCapability.AI_MODEL_CAPABILITY_UNKNOWN)
    ..aOM<AIProviderGrant>(3, _omitFieldNames ? '' : 'grant', subBuilder: AIProviderGrant.create)
    ..aOM<AIProvider>(4, _omitFieldNames ? '' : 'provider', subBuilder: AIProvider.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIModel clone() => AIModel()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIModel copyWith(void Function(AIModel) updates) => super.copyWith((message) => updates(message as AIModel)) as AIModel;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIModel create() => AIModel._();
  AIModel createEmptyInstance() => create();
  static $pb.PbList<AIModel> createRepeated() => $pb.PbList<AIModel>();
  @$core.pragma('dart2js:noInline')
  static AIModel getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIModel>(create);
  static AIModel? _defaultInstance;

  /// The exact model name to use when calling the provider (e.g. `"gemini-3.1-flash-image"`).
  @$pb.TagNumber(1)
  $core.String get modelName => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelName($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelName() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelName() => clearField(1);

  /// What this model can actually do - from the server's own hardcoded catalog for
  /// `provider.provider`'s variant (see [`AIModelCapability`](#rellm-AIModelCapability)), not
  /// anything reported by the provider's API itself. Feature gating keys off this rather than
  /// `model_name` directly, so e.g. [`GenerateMedia`](#grpc-api-GenerateMedia) (which needs
  /// `AI_MODEL_CAPABILITY_IMAGE_EDITING` whenever `GenerateMediaRequest.media_ids` is non-empty, or
  /// just `AI_MODEL_CAPABILITY_IMAGE_GENERATION` when it's empty) doesn't need its own hardcoded
  /// list of model names.
  @$pb.TagNumber(2)
  $core.List<AIModelCapability> get capabilities => $_getList(1);

  /// The grant that allows this access, when the current user isn't `provider.owner` themselves.
  /// Unset when the current user owns `provider` outright (full, ungated access - no grant needed).
  @$pb.TagNumber(3)
  AIProviderGrant get grant => $_getN(2);
  @$pb.TagNumber(3)
  set grant(AIProviderGrant v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasGrant() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrant() => clearField(3);
  @$pb.TagNumber(3)
  AIProviderGrant ensureGrant() => $_ensure(2);

  /// The provider this model belongs to. Its own `grants` list is only populated when the current
  /// user is `provider.owner` (or an Admin) - see [`GetAIProviders`](#grpc-api-GetAIProviders)'s own doc; a
  /// mere grantee never sees who else has been granted access to a provider they don't own.
  @$pb.TagNumber(4)
  AIProvider get provider => $_getN(3);
  @$pb.TagNumber(4)
  set provider(AIProvider v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasProvider() => $_has(3);
  @$pb.TagNumber(4)
  void clearProvider() => clearField(4);
  @$pb.TagNumber(4)
  AIProvider ensureProvider() => $_ensure(3);
}

enum GenerateMediaRequest_Target {
  postId, 
  occasionId, 
  notSet
}

/// Request to generate (or edit) an image via one of the current user's
/// [`AIModel`](#rellm-AIModel)s - see [`GenerateMedia`](#grpc-api-GenerateMedia). The resulting
/// image is stored as a new [`Media`](#rellm-Media) (`generated = true`) owned by the current user, and - if
/// `target` is set - prepended as the *first* item in that Post's (or Event's own Post's) `media` list.
class GenerateMediaRequest extends $pb.GeneratedMessage {
  factory GenerateMediaRequest({
    AIModel? model,
    $core.String? userPrompt,
    $core.Iterable<$core.String>? mediaIds,
    $core.String? postId,
    $core.String? occasionId,
  }) {
    final $result = create();
    if (model != null) {
      $result.model = model;
    }
    if (userPrompt != null) {
      $result.userPrompt = userPrompt;
    }
    if (mediaIds != null) {
      $result.mediaIds.addAll(mediaIds);
    }
    if (postId != null) {
      $result.postId = postId;
    }
    if (occasionId != null) {
      $result.occasionId = occasionId;
    }
    return $result;
  }
  GenerateMediaRequest._() : super();
  factory GenerateMediaRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GenerateMediaRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, GenerateMediaRequest_Target> _GenerateMediaRequest_TargetByTag = {
    5 : GenerateMediaRequest_Target.postId,
    6 : GenerateMediaRequest_Target.occasionId,
    0 : GenerateMediaRequest_Target.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GenerateMediaRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [5, 6])
    ..aOM<AIModel>(1, _omitFieldNames ? '' : 'model', subBuilder: AIModel.create)
    ..aOS(2, _omitFieldNames ? '' : 'userPrompt')
    ..pPS(3, _omitFieldNames ? '' : 'mediaIds')
    ..aOS(5, _omitFieldNames ? '' : 'postId')
    ..aOS(6, _omitFieldNames ? '' : 'occasionId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GenerateMediaRequest clone() => GenerateMediaRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GenerateMediaRequest copyWith(void Function(GenerateMediaRequest) updates) => super.copyWith((message) => updates(message as GenerateMediaRequest)) as GenerateMediaRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerateMediaRequest create() => GenerateMediaRequest._();
  GenerateMediaRequest createEmptyInstance() => create();
  static $pb.PbList<GenerateMediaRequest> createRepeated() => $pb.PbList<GenerateMediaRequest>();
  @$core.pragma('dart2js:noInline')
  static GenerateMediaRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GenerateMediaRequest>(create);
  static GenerateMediaRequest? _defaultInstance;

  GenerateMediaRequest_Target whichTarget() => _GenerateMediaRequest_TargetByTag[$_whichOneof(0)]!;
  void clearTarget() => clearField($_whichOneof(0));

  /// Which of the current user's `AIModel`s to generate with - `model.model_name` selects the actual
  /// model, `model.provider.id` identifies whose `AIProvider` (the current user's own, or one they've been
  /// granted access to) to call it through. Only `model_name`/`provider.id` are read server-side - any other field
  /// sent here (e.g. a spoofed `grant`) is ignored in favor of the caller's real access, re-derived from
  /// `provider.id` and the current user.
  @$pb.TagNumber(1)
  AIModel get model => $_getN(0);
  @$pb.TagNumber(1)
  set model(AIModel v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasModel() => $_has(0);
  @$pb.TagNumber(1)
  void clearModel() => clearField(1);
  @$pb.TagNumber(1)
  AIModel ensureModel() => $_ensure(0);

  /// The user-editable prompt describing what to generate, e.g. "Please generate a square headline poster for the
  /// following event." Combined server-side with `target`'s own formatted content (title/description/date-time
  /// range/location - the same formatting [`SyncDestination`](#rellm-SyncDestination)s use) before being sent to
  /// the model, so the user never has to paste that context in by hand.
  @$pb.TagNumber(2)
  $core.String get userPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set userPrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserPrompt() => clearField(2);

  /// Existing [`Media`](#rellm-Media) to pass to the model alongside `user_prompt`, for image editing/
  /// reference-based generation (e.g. a target Post/Event's own current photos), in the order given here. Leave
  /// empty for plain text-to-image generation instead - `model` must have the matching capability either way
  /// (`AI_MODEL_CAPABILITY_IMAGE_EDITING` here, `AI_MODEL_CAPABILITY_IMAGE_GENERATION` if empty - see
  /// [`AIModelCapability`](#rellm-AIModelCapability)'s own doc). Every id must be owned by the current user (or
  /// the current user must be an Admin).
  @$pb.TagNumber(3)
  $core.List<$core.String> get mediaIds => $_getList(2);

  /// Attach to (and use the content of) this Post. Caller must be its author, or an Admin.
  @$pb.TagNumber(5)
  $core.String get postId => $_getSZ(3);
  @$pb.TagNumber(5)
  set postId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(5)
  $core.bool hasPostId() => $_has(3);
  @$pb.TagNumber(5)
  void clearPostId() => clearField(5);

  /// Attach to (and use the content of) this Occasion's parent Event's own Post - named by
  /// Occasion, not Event, since that's what a viewer is actually looking at (and what gives
  /// the generated prompt its date/time/location context, the same way
  /// [`SyncOccasion`](#grpc-api-SyncOccasion) does). Caller must be the Event's own
  /// Post's author, or hold `MODERATE_POSTS`/`MODERATE_EVENTS`, or be an Admin.
  @$pb.TagNumber(6)
  $core.String get occasionId => $_getSZ(4);
  @$pb.TagNumber(6)
  set occasionId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(6)
  $core.bool hasOccasionId() => $_has(4);
  @$pb.TagNumber(6)
  void clearOccasionId() => clearField(6);
}

enum AIProvider_Provider {
  geminiCredentials, 
  openaiCredentials, 
  anthropicCredentials, 
  digitaloceanCredentials, 
  notSet
}

///  An AIProvider is a user-owned connection to an external AI model API (e.g. a Gemini API
///  key), which its owner can grant other users of this server metered, budgeted access to. Mirrors
///  [`SyncDestination`](#rellm-SyncDestination)/[`SyncSource`](#rellm-SyncSource) (also user-owned integrations
///  with an [`Author`](#rellm-Author) `owner` and a `oneof` naming which external system is configured), but where
///  those push/pull content, an AIProvider is metered *access* to a third-party LLM API - shared out to
///  other users via [`AIProviderGrant`](#rellm-AIProviderGrant)s rather than posted-to/subscribed-from.
///
///  Providers are managed via [`GetAIProviders`](#grpc-api-GetAIProviders),
///  [`CreateAIProvider`](#grpc-api-CreateAIProvider) (requires `CREATE_AI_PROVIDERS`, or Admin),
///  [`UpdateAIProvider`](#grpc-api-UpdateAIProvider) (owner, or Admin for any user's), and
///  [`DeleteAIProvider`](#grpc-api-DeleteAIProvider) (owner, or Admin) - the same self-or-Admin shape as
///  [`SyncDestination`](#rellm-SyncDestination)'s RPCs. Access to a provider is granted/revoked to other users via
///  [`GrantAIProvider`](#grpc-api-GrantAIProvider)/[`RevokeAIProvider`](#grpc-api-RevokeAIProvider) which,
///  unlike every other RPC pair here, are **owner-only with no Admin override**: an Admin can manage the provider
///  record itself (rename it, rotate its key, delete it), but handing out access to *someone else's* API budget is a
///  call only its owner should be able to make.
///
///  [`GeminiCredentials`](#rellm-GeminiCredentials)/[`OpenAICredentials`](#rellm-OpenAICredentials)/
///  [`DigitalOceanCredentials`](#rellm-DigitalOceanCredentials) all have a working connection flow (Gemini's
///  Interactions API, OpenAI's Images API, DigitalOcean's Serverless Inference API - the last of which is also
///  OpenAI-Images-API-shaped, just a different base URL/key and generation-only, no editing endpoint);
///  [`AnthropicCredentials`](#rellm-AnthropicCredentials) is defined for forward compatibility but is not yet
///  accepted by [`CreateAIProvider`](#grpc-api-CreateAIProvider) (Anthropic doesn't offer image generation).
class AIProvider extends $pb.GeneratedMessage {
  factory AIProvider({
    $core.String? id,
    $5.Author? owner,
    $core.String? name,
    GeminiCredentials? geminiCredentials,
    OpenAICredentials? openaiCredentials,
    AnthropicCredentials? anthropicCredentials,
    DigitalOceanCredentials? digitaloceanCredentials,
    $core.Iterable<AIProviderGrant>? grants,
    $12.Timestamp? createdAt,
    $12.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (owner != null) {
      $result.owner = owner;
    }
    if (name != null) {
      $result.name = name;
    }
    if (geminiCredentials != null) {
      $result.geminiCredentials = geminiCredentials;
    }
    if (openaiCredentials != null) {
      $result.openaiCredentials = openaiCredentials;
    }
    if (anthropicCredentials != null) {
      $result.anthropicCredentials = anthropicCredentials;
    }
    if (digitaloceanCredentials != null) {
      $result.digitaloceanCredentials = digitaloceanCredentials;
    }
    if (grants != null) {
      $result.grants.addAll(grants);
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  AIProvider._() : super();
  factory AIProvider.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIProvider.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, AIProvider_Provider> _AIProvider_ProviderByTag = {
    4 : AIProvider_Provider.geminiCredentials,
    5 : AIProvider_Provider.openaiCredentials,
    6 : AIProvider_Provider.anthropicCredentials,
    7 : AIProvider_Provider.digitaloceanCredentials,
    0 : AIProvider_Provider.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIProvider', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..oo(0, [4, 5, 6, 7])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'owner', subBuilder: $5.Author.create)
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOM<GeminiCredentials>(4, _omitFieldNames ? '' : 'geminiCredentials', subBuilder: GeminiCredentials.create)
    ..aOM<OpenAICredentials>(5, _omitFieldNames ? '' : 'openaiCredentials', subBuilder: OpenAICredentials.create)
    ..aOM<AnthropicCredentials>(6, _omitFieldNames ? '' : 'anthropicCredentials', subBuilder: AnthropicCredentials.create)
    ..aOM<DigitalOceanCredentials>(7, _omitFieldNames ? '' : 'digitaloceanCredentials', subBuilder: DigitalOceanCredentials.create)
    ..pc<AIProviderGrant>(14, _omitFieldNames ? '' : 'grants', $pb.PbFieldType.PM, subBuilder: AIProviderGrant.create)
    ..aOM<$12.Timestamp>(15, _omitFieldNames ? '' : 'createdAt', subBuilder: $12.Timestamp.create)
    ..aOM<$12.Timestamp>(16, _omitFieldNames ? '' : 'updatedAt', subBuilder: $12.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIProvider clone() => AIProvider()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIProvider copyWith(void Function(AIProvider) updates) => super.copyWith((message) => updates(message as AIProvider)) as AIProvider;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIProvider create() => AIProvider._();
  AIProvider createEmptyInstance() => create();
  static $pb.PbList<AIProvider> createRepeated() => $pb.PbList<AIProvider>();
  @$core.pragma('dart2js:noInline')
  static AIProvider getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIProvider>(create);
  static AIProvider? _defaultInstance;

  AIProvider_Provider whichProvider() => _AIProvider_ProviderByTag[$_whichOneof(0)]!;
  void clearProvider() => clearField($_whichOneof(0));

  /// Unique ID for the AIProvider.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The user information for the owner of this AIProvider - the only user (besides Admins) who may
  /// rename it or change its credentials/provider, and the *only* user (not even Admins) who may grant/revoke other
  /// users' access to it.
  @$pb.TagNumber(2)
  $5.Author get owner => $_getN(1);
  @$pb.TagNumber(2)
  set owner($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwner() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwner() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureOwner() => $_ensure(1);

  /// A display name for the provider, chosen by its owner (e.g. "My Gemini Key", "Team OpenAI Account"). Purely
  /// cosmetic - has no effect on behavior.
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => clearField(3);

  /// A [Google Gemini API](https://ai.google.dev/gemini-api) connection, used for image generation/editing (e.g.
  /// generating Event posters) via its [Interactions API](https://ai.google.dev/gemini-api/docs/image-generation).
  @$pb.TagNumber(4)
  GeminiCredentials get geminiCredentials => $_getN(3);
  @$pb.TagNumber(4)
  set geminiCredentials(GeminiCredentials v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasGeminiCredentials() => $_has(3);
  @$pb.TagNumber(4)
  void clearGeminiCredentials() => clearField(4);
  @$pb.TagNumber(4)
  GeminiCredentials ensureGeminiCredentials() => $_ensure(3);

  /// An [OpenAI API](https://platform.openai.com/docs/api-reference) connection, used for image
  /// generation/editing via its [Images API](https://platform.openai.com/docs/guides/image-generation) (GPT Image models).
  @$pb.TagNumber(5)
  OpenAICredentials get openaiCredentials => $_getN(4);
  @$pb.TagNumber(5)
  set openaiCredentials(OpenAICredentials v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasOpenaiCredentials() => $_has(4);
  @$pb.TagNumber(5)
  void clearOpenaiCredentials() => clearField(5);
  @$pb.TagNumber(5)
  OpenAICredentials ensureOpenaiCredentials() => $_ensure(4);

  /// An [Anthropic API](https://docs.anthropic.com) connection. *Not yet creatable* - Anthropic doesn't offer an image generation API.
  @$pb.TagNumber(6)
  AnthropicCredentials get anthropicCredentials => $_getN(5);
  @$pb.TagNumber(6)
  set anthropicCredentials(AnthropicCredentials v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasAnthropicCredentials() => $_has(5);
  @$pb.TagNumber(6)
  void clearAnthropicCredentials() => clearField(6);
  @$pb.TagNumber(6)
  AnthropicCredentials ensureAnthropicCredentials() => $_ensure(5);

  /// A [DigitalOcean Gradient AI Platform](https://docs.digitalocean.com/products/gradient-ai-platform/) /
  /// Serverless Inference connection, used for image generation (no editing - DigitalOcean's
  /// [Serverless Inference API](https://docs.digitalocean.com/products/gradient-ai-platform/reference/api/serverless-inference/)
  /// has no `/v1/images/edits`-equivalent endpoint) via its OpenAI-Images-API-shaped
  /// `/v1/images/generations` endpoint (GPT Image and Stable Diffusion models, re-hosted under DigitalOcean's own
  /// billing).
  @$pb.TagNumber(7)
  DigitalOceanCredentials get digitaloceanCredentials => $_getN(6);
  @$pb.TagNumber(7)
  set digitaloceanCredentials(DigitalOceanCredentials v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasDigitaloceanCredentials() => $_has(6);
  @$pb.TagNumber(7)
  void clearDigitaloceanCredentials() => clearField(7);
  @$pb.TagNumber(7)
  DigitalOceanCredentials ensureDigitaloceanCredentials() => $_ensure(6);

  /// Other users this provider's owner has granted metered access to, via
  /// [`GrantAIProvider`](#grpc-api-GrantAIProvider). Only ever populated for the owner (or an Admin) --
  /// see [`GetAIProviders`](#grpc-api-GetAIProviders).
  @$pb.TagNumber(14)
  $core.List<AIProviderGrant> get grants => $_getList(7);

  /// The time the provider was created.
  @$pb.TagNumber(15)
  $12.Timestamp get createdAt => $_getN(8);
  @$pb.TagNumber(15)
  set createdAt($12.Timestamp v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasCreatedAt() => $_has(8);
  @$pb.TagNumber(15)
  void clearCreatedAt() => clearField(15);
  @$pb.TagNumber(15)
  $12.Timestamp ensureCreatedAt() => $_ensure(8);

  /// The time the provider was last updated (renamed, or had its provider/credentials changed).
  @$pb.TagNumber(16)
  $12.Timestamp get updatedAt => $_getN(9);
  @$pb.TagNumber(16)
  set updatedAt($12.Timestamp v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasUpdatedAt() => $_has(9);
  @$pb.TagNumber(16)
  void clearUpdatedAt() => clearField(16);
  @$pb.TagNumber(16)
  $12.Timestamp ensureUpdatedAt() => $_ensure(9);
}

/// A grant of metered access to someone else's [`AIProvider`](#rellm-AIProvider), created/reset via
/// [`GrantAIProvider`](#grpc-api-GrantAIProvider) and removed via
/// [`RevokeAIProvider`](#grpc-api-RevokeAIProvider). Upserted on the unique
/// `(ai_provider_id, ai_model_grantee)` pair - calling [`GrantAIProvider`](#grpc-api-GrantAIProvider)
/// again for a user who already has a grant *resets* `tokens_remaining` to the newly-requested amount, it does not
/// add to it.
class AIProviderGrant extends $pb.GeneratedMessage {
  factory AIProviderGrant({
    $core.String? aiProviderId,
    $5.Author? aiModelGrantee,
    $core.Iterable<$core.String>? modelNames,
    $fixnum.Int64? tokensRemaining,
    $fixnum.Int64? overage,
    $12.Timestamp? createdAt,
    $12.Timestamp? updatedAt,
  }) {
    final $result = create();
    if (aiProviderId != null) {
      $result.aiProviderId = aiProviderId;
    }
    if (aiModelGrantee != null) {
      $result.aiModelGrantee = aiModelGrantee;
    }
    if (modelNames != null) {
      $result.modelNames.addAll(modelNames);
    }
    if (tokensRemaining != null) {
      $result.tokensRemaining = tokensRemaining;
    }
    if (overage != null) {
      $result.overage = overage;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  AIProviderGrant._() : super();
  factory AIProviderGrant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AIProviderGrant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AIProviderGrant', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'aiProviderId')
    ..aOM<$5.Author>(2, _omitFieldNames ? '' : 'aiModelGrantee', subBuilder: $5.Author.create)
    ..pPS(3, _omitFieldNames ? '' : 'modelNames')
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'tokensRemaining', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'overage', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<$12.Timestamp>(15, _omitFieldNames ? '' : 'createdAt', subBuilder: $12.Timestamp.create)
    ..aOM<$12.Timestamp>(16, _omitFieldNames ? '' : 'updatedAt', subBuilder: $12.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AIProviderGrant clone() => AIProviderGrant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AIProviderGrant copyWith(void Function(AIProviderGrant) updates) => super.copyWith((message) => updates(message as AIProviderGrant)) as AIProviderGrant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AIProviderGrant create() => AIProviderGrant._();
  AIProviderGrant createEmptyInstance() => create();
  static $pb.PbList<AIProviderGrant> createRepeated() => $pb.PbList<AIProviderGrant>();
  @$core.pragma('dart2js:noInline')
  static AIProviderGrant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AIProviderGrant>(create);
  static AIProviderGrant? _defaultInstance;

  /// The ID of the [`AIProvider`](#rellm-AIProvider) this grant is for.
  @$pb.TagNumber(1)
  $core.String get aiProviderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set aiProviderId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAiProviderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAiProviderId() => clearField(1);

  /// The user this access was granted to.
  @$pb.TagNumber(2)
  $5.Author get aiModelGrantee => $_getN(1);
  @$pb.TagNumber(2)
  set aiModelGrantee($5.Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAiModelGrantee() => $_has(1);
  @$pb.TagNumber(2)
  void clearAiModelGrantee() => clearField(2);
  @$pb.TagNumber(2)
  $5.Author ensureAiModelGrantee() => $_ensure(1);

  /// The model name (that will be used to call the provider) that the grantee is allowed to use by this grant.
  /// If blank, allows access to any models the provider supports. If non-blank, the grantee is only allowed to use the model(s) specified here.
  /// Allows granters to set per-model (or per-model-group) token budgets, e.g. "gpt-4" vs "gpt-3.5-turbo".
  @$pb.TagNumber(3)
  $core.List<$core.String> get modelNames => $_getList(2);

  /// The number of tokens the grantee may still spend against this provider. Set (and reset) by the owner via
  /// [`GrantAIProvider`](#grpc-api-GrantAIProvider). Once this reaches 0, [`GenerateMedia`](#grpc-api-GenerateMedia)
  /// stops working for the grantee entirely, until the owner grants more via
  /// [`GrantAIProvider`](#grpc-api-GrantAIProvider) again.
  @$pb.TagNumber(4)
  $fixnum.Int64 get tokensRemaining => $_getI64(3);
  @$pb.TagNumber(4)
  set tokensRemaining($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTokensRemaining() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensRemaining() => clearField(4);

  /// How far a single [`GenerateMedia`](#grpc-api-GenerateMedia) call's actual token usage overshot `tokens_remaining`
  /// the moment it hit 0 - effectively a "negative `tokens_remaining`" (which, being `uint64`, can't represent a
  /// negative value directly), recorded here instead as a positive debt for the owner's own visibility. E.g. a
  /// grantee with 30 tokens left whose next call actually costs 45 ends up with `tokens_remaining = 0` and
  /// `overage = 15`. Always 0 immediately after a fresh [`GrantAIProvider`](#grpc-api-GrantAIProvider) call
  /// (any prior debt is cleared, not carried forward) - see that RPC's own doc.
  @$pb.TagNumber(5)
  $fixnum.Int64 get overage => $_getI64(4);
  @$pb.TagNumber(5)
  set overage($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOverage() => $_has(4);
  @$pb.TagNumber(5)
  void clearOverage() => clearField(5);

  /// The time the grant was first created.
  @$pb.TagNumber(15)
  $12.Timestamp get createdAt => $_getN(5);
  @$pb.TagNumber(15)
  set createdAt($12.Timestamp v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasCreatedAt() => $_has(5);
  @$pb.TagNumber(15)
  void clearCreatedAt() => clearField(15);
  @$pb.TagNumber(15)
  $12.Timestamp ensureCreatedAt() => $_ensure(5);

  /// The time the grant was last updated (i.e. last reset by another
  /// [`GrantAIProvider`](#grpc-api-GrantAIProvider) call).
  @$pb.TagNumber(16)
  $12.Timestamp get updatedAt => $_getN(6);
  @$pb.TagNumber(16)
  set updatedAt($12.Timestamp v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasUpdatedAt() => $_has(6);
  @$pb.TagNumber(16)
  void clearUpdatedAt() => clearField(16);
  @$pb.TagNumber(16)
  $12.Timestamp ensureUpdatedAt() => $_ensure(6);
}

/// Response to a request for a user's [`AIProvider`](#rellm-AIProvider)s.
class GetAIProvidersResponse extends $pb.GeneratedMessage {
  factory GetAIProvidersResponse({
    $core.Iterable<AIProvider>? providers,
    $core.Iterable<AIModel>? aiModels,
  }) {
    final $result = create();
    if (providers != null) {
      $result.providers.addAll(providers);
    }
    if (aiModels != null) {
      $result.aiModels.addAll(aiModels);
    }
    return $result;
  }
  GetAIProvidersResponse._() : super();
  factory GetAIProvidersResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetAIProvidersResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetAIProvidersResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<AIProvider>(1, _omitFieldNames ? '' : 'providers', $pb.PbFieldType.PM, subBuilder: AIProvider.create)
    ..pc<AIModel>(2, _omitFieldNames ? '' : 'aiModels', $pb.PbFieldType.PM, subBuilder: AIModel.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetAIProvidersResponse clone() => GetAIProvidersResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetAIProvidersResponse copyWith(void Function(GetAIProvidersResponse) updates) => super.copyWith((message) => updates(message as GetAIProvidersResponse)) as GetAIProvidersResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetAIProvidersResponse create() => GetAIProvidersResponse._();
  GetAIProvidersResponse createEmptyInstance() => create();
  static $pb.PbList<GetAIProvidersResponse> createRepeated() => $pb.PbList<GetAIProvidersResponse>();
  @$core.pragma('dart2js:noInline')
  static GetAIProvidersResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetAIProvidersResponse>(create);
  static GetAIProvidersResponse? _defaultInstance;

  /// The requested user's own AIProviders (those they own) - exactly the distinct `provider`s
  /// in `ai_models` whose `owner` is the requested user, each with its own `grants`
  /// populated (who else can use it). A convenience duplicate of data already in
  /// `ai_models`, so callers managing a user's own providers (rename/rekey/delete/grant/
  /// revoke) don't have to de-duplicate that list themselves.
  @$pb.TagNumber(1)
  $core.List<AIProvider> get providers => $_getList(0);

  /// Every model the requested user may currently call - their own providers' models, plus any
  /// models granted to them on other users' providers. See [`AIModel`](#rellm-AIModel)'s own doc.
  @$pb.TagNumber(2)
  $core.List<AIModel> get aiModels => $_getList(1);
}

/// Request to delete an AIProvider. Also deletes any of its [`AIProviderGrant`](#rellm-AIProviderGrant)s.
class DeleteAIProviderRequest extends $pb.GeneratedMessage {
  factory DeleteAIProviderRequest({
    AIProvider? provider,
  }) {
    final $result = create();
    if (provider != null) {
      $result.provider = provider;
    }
    return $result;
  }
  DeleteAIProviderRequest._() : super();
  factory DeleteAIProviderRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeleteAIProviderRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeleteAIProviderRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<AIProvider>(1, _omitFieldNames ? '' : 'provider', subBuilder: AIProvider.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeleteAIProviderRequest clone() => DeleteAIProviderRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeleteAIProviderRequest copyWith(void Function(DeleteAIProviderRequest) updates) => super.copyWith((message) => updates(message as DeleteAIProviderRequest)) as DeleteAIProviderRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteAIProviderRequest create() => DeleteAIProviderRequest._();
  DeleteAIProviderRequest createEmptyInstance() => create();
  static $pb.PbList<DeleteAIProviderRequest> createRepeated() => $pb.PbList<DeleteAIProviderRequest>();
  @$core.pragma('dart2js:noInline')
  static DeleteAIProviderRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteAIProviderRequest>(create);
  static DeleteAIProviderRequest? _defaultInstance;

  /// The provider to be deleted.
  @$pb.TagNumber(1)
  AIProvider get provider => $_getN(0);
  @$pb.TagNumber(1)
  set provider(AIProvider v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasProvider() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvider() => clearField(1);
  @$pb.TagNumber(1)
  AIProvider ensureProvider() => $_ensure(0);
}

/// Request to grant (or reset) another user's metered access to one of the current user's
/// [`AIProvider`](#rellm-AIProvider)s. *Authenticated, owner-only - no Admin override.*
class GrantAIProviderRequest extends $pb.GeneratedMessage {
  factory GrantAIProviderRequest({
    $core.String? userId,
    $core.String? aiProviderId,
    $fixnum.Int64? tokens,
    $core.Iterable<$core.String>? modelNames,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (aiProviderId != null) {
      $result.aiProviderId = aiProviderId;
    }
    if (tokens != null) {
      $result.tokens = tokens;
    }
    if (modelNames != null) {
      $result.modelNames.addAll(modelNames);
    }
    return $result;
  }
  GrantAIProviderRequest._() : super();
  factory GrantAIProviderRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GrantAIProviderRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GrantAIProviderRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'aiProviderId')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'tokens', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(4, _omitFieldNames ? '' : 'modelNames')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GrantAIProviderRequest clone() => GrantAIProviderRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GrantAIProviderRequest copyWith(void Function(GrantAIProviderRequest) updates) => super.copyWith((message) => updates(message as GrantAIProviderRequest)) as GrantAIProviderRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GrantAIProviderRequest create() => GrantAIProviderRequest._();
  GrantAIProviderRequest createEmptyInstance() => create();
  static $pb.PbList<GrantAIProviderRequest> createRepeated() => $pb.PbList<GrantAIProviderRequest>();
  @$core.pragma('dart2js:noInline')
  static GrantAIProviderRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GrantAIProviderRequest>(create);
  static GrantAIProviderRequest? _defaultInstance;

  /// The user to grant access to.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The AIProvider to grant access to. Must be owned by the caller.
  @$pb.TagNumber(2)
  $core.String get aiProviderId => $_getSZ(1);
  @$pb.TagNumber(2)
  set aiProviderId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAiProviderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAiProviderId() => clearField(2);

  /// The number of tokens the grantee may spend. Calling this RPC again for the same
  /// (`ai_provider_id`, `user_id`) pair *replaces*, rather than adds to, this value.
  @$pb.TagNumber(3)
  $fixnum.Int64 get tokens => $_getI64(2);
  @$pb.TagNumber(3)
  set tokens($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearTokens() => clearField(3);

  /// The models the grantee is allowed to use, mirroring [`AIProviderGrant.model_names`](#rellm-AIProviderGrant)
  /// - if empty, allows access to any model the provider supports. Also replaced (not merged)
  /// on a repeat call, same as `tokens`.
  @$pb.TagNumber(4)
  $core.List<$core.String> get modelNames => $_getList(3);
}

/// Request to revoke another user's access to one of the current user's
/// [`AIProvider`](#rellm-AIProvider)s, the reverse of
/// [`GrantAIProvider`](#grpc-api-GrantAIProvider). *Authenticated, owner-only - no Admin override.*
class RevokeAIProviderRequest extends $pb.GeneratedMessage {
  factory RevokeAIProviderRequest({
    $core.String? userId,
    $core.String? aiProviderId,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (aiProviderId != null) {
      $result.aiProviderId = aiProviderId;
    }
    return $result;
  }
  RevokeAIProviderRequest._() : super();
  factory RevokeAIProviderRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RevokeAIProviderRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RevokeAIProviderRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'aiProviderId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RevokeAIProviderRequest clone() => RevokeAIProviderRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RevokeAIProviderRequest copyWith(void Function(RevokeAIProviderRequest) updates) => super.copyWith((message) => updates(message as RevokeAIProviderRequest)) as RevokeAIProviderRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeAIProviderRequest create() => RevokeAIProviderRequest._();
  RevokeAIProviderRequest createEmptyInstance() => create();
  static $pb.PbList<RevokeAIProviderRequest> createRepeated() => $pb.PbList<RevokeAIProviderRequest>();
  @$core.pragma('dart2js:noInline')
  static RevokeAIProviderRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RevokeAIProviderRequest>(create);
  static RevokeAIProviderRequest? _defaultInstance;

  /// The user whose access should be revoked.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// The AIProvider to revoke access to. Must be owned by the caller.
  @$pb.TagNumber(2)
  $core.String get aiProviderId => $_getSZ(1);
  @$pb.TagNumber(2)
  set aiProviderId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAiProviderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAiProviderId() => clearField(2);
}

/// Credentials for a [Google Gemini API](https://ai.google.dev/gemini-api) connection - the only
/// [`AIProvider.provider`](#rellm-AIProvider) variant currently accepted by
/// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
/// Used for image generation/editing via Gemini's [Interactions API](https://ai.google.dev/gemini-api/docs/image-generation),
/// e.g. to generate/edit Event posters from an Event's own content - see [`GenerateMedia`](#grpc-api-GenerateMedia).
class GeminiCredentials extends $pb.GeneratedMessage {
  factory GeminiCredentials({
    $core.String? geminiApiKey,
  }) {
    final $result = create();
    if (geminiApiKey != null) {
      $result.geminiApiKey = geminiApiKey;
    }
    return $result;
  }
  GeminiCredentials._() : super();
  factory GeminiCredentials.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GeminiCredentials.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GeminiCredentials', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'geminiApiKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GeminiCredentials clone() => GeminiCredentials()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GeminiCredentials copyWith(void Function(GeminiCredentials) updates) => super.copyWith((message) => updates(message as GeminiCredentials)) as GeminiCredentials;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GeminiCredentials create() => GeminiCredentials._();
  GeminiCredentials createEmptyInstance() => create();
  static $pb.PbList<GeminiCredentials> createRepeated() => $pb.PbList<GeminiCredentials>();
  @$core.pragma('dart2js:noInline')
  static GeminiCredentials getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GeminiCredentials>(create);
  static GeminiCredentials? _defaultInstance;

  /// The Gemini API key. Required (and only used) on
  /// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) --
  /// **never populated in responses**, the same write-only convention as e.g.
  /// [`MastodonAccount.access_token`](#rellm-MastodonAccount) in `sync.proto`.
  @$pb.TagNumber(1)
  $core.String get geminiApiKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set geminiApiKey($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGeminiApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearGeminiApiKey() => clearField(1);
}

/// Credentials for an [OpenAI API](https://platform.openai.com/docs/api-reference) connection, accepted by
/// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
/// Used for image generation/editing via OpenAI's [Images API](https://platform.openai.com/docs/guides/image-generation)
/// (the GPT Image model family) - same use case as [`GeminiCredentials`](#rellm-GeminiCredentials), see
/// [`GenerateMedia`](#grpc-api-GenerateMedia).
class OpenAICredentials extends $pb.GeneratedMessage {
  factory OpenAICredentials({
    $core.String? openaiApiKey,
  }) {
    final $result = create();
    if (openaiApiKey != null) {
      $result.openaiApiKey = openaiApiKey;
    }
    return $result;
  }
  OpenAICredentials._() : super();
  factory OpenAICredentials.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OpenAICredentials.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OpenAICredentials', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'openaiApiKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OpenAICredentials clone() => OpenAICredentials()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OpenAICredentials copyWith(void Function(OpenAICredentials) updates) => super.copyWith((message) => updates(message as OpenAICredentials)) as OpenAICredentials;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OpenAICredentials create() => OpenAICredentials._();
  OpenAICredentials createEmptyInstance() => create();
  static $pb.PbList<OpenAICredentials> createRepeated() => $pb.PbList<OpenAICredentials>();
  @$core.pragma('dart2js:noInline')
  static OpenAICredentials getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OpenAICredentials>(create);
  static OpenAICredentials? _defaultInstance;

  /// The OpenAI API key. Required (and only used) on
  /// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) --
  /// never populated in responses (see [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)).
  @$pb.TagNumber(1)
  $core.String get openaiApiKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set openaiApiKey($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOpenaiApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpenaiApiKey() => clearField(1);
}

/// Credentials for a [DigitalOcean Gradient AI Platform](https://docs.digitalocean.com/products/gradient-ai-platform/) /
/// Serverless Inference connection, accepted by
/// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider).
/// Used for image *generation only* (no editing - see `AIProvider.provider`'s own doc on this variant) via its
/// [Serverless Inference API](https://docs.digitalocean.com/products/gradient-ai-platform/reference/api/serverless-inference/)
/// `/v1/images/generations` endpoint, OpenAI-Images-API-shaped and re-hosting GPT Image and Stable Diffusion models --
/// see [`GenerateMedia`](#grpc-api-GenerateMedia).
class DigitalOceanCredentials extends $pb.GeneratedMessage {
  factory DigitalOceanCredentials({
    $core.String? digitaloceanApiKey,
  }) {
    final $result = create();
    if (digitaloceanApiKey != null) {
      $result.digitaloceanApiKey = digitaloceanApiKey;
    }
    return $result;
  }
  DigitalOceanCredentials._() : super();
  factory DigitalOceanCredentials.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DigitalOceanCredentials.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DigitalOceanCredentials', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'digitaloceanApiKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DigitalOceanCredentials clone() => DigitalOceanCredentials()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DigitalOceanCredentials copyWith(void Function(DigitalOceanCredentials) updates) => super.copyWith((message) => updates(message as DigitalOceanCredentials)) as DigitalOceanCredentials;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DigitalOceanCredentials create() => DigitalOceanCredentials._();
  DigitalOceanCredentials createEmptyInstance() => create();
  static $pb.PbList<DigitalOceanCredentials> createRepeated() => $pb.PbList<DigitalOceanCredentials>();
  @$core.pragma('dart2js:noInline')
  static DigitalOceanCredentials getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DigitalOceanCredentials>(create);
  static DigitalOceanCredentials? _defaultInstance;

  /// The DigitalOcean Serverless Inference API token. Required (and only used) on
  /// [`CreateAIProvider`](#grpc-api-CreateAIProvider)/[`UpdateAIProvider`](#grpc-api-UpdateAIProvider) --
  /// never populated in responses (see [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)).
  @$pb.TagNumber(1)
  $core.String get digitaloceanApiKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set digitaloceanApiKey($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDigitaloceanApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearDigitaloceanApiKey() => clearField(1);
}

/// Credentials for an [Anthropic API](https://docs.anthropic.com) connection. *Not yet creatable* - defined for
/// forward compatibility only.
class AnthropicCredentials extends $pb.GeneratedMessage {
  factory AnthropicCredentials({
    $core.String? anthropicApiKey,
  }) {
    final $result = create();
    if (anthropicApiKey != null) {
      $result.anthropicApiKey = anthropicApiKey;
    }
    return $result;
  }
  AnthropicCredentials._() : super();
  factory AnthropicCredentials.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AnthropicCredentials.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AnthropicCredentials', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'anthropicApiKey')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AnthropicCredentials clone() => AnthropicCredentials()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AnthropicCredentials copyWith(void Function(AnthropicCredentials) updates) => super.copyWith((message) => updates(message as AnthropicCredentials)) as AnthropicCredentials;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AnthropicCredentials create() => AnthropicCredentials._();
  AnthropicCredentials createEmptyInstance() => create();
  static $pb.PbList<AnthropicCredentials> createRepeated() => $pb.PbList<AnthropicCredentials>();
  @$core.pragma('dart2js:noInline')
  static AnthropicCredentials getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AnthropicCredentials>(create);
  static AnthropicCredentials? _defaultInstance;

  /// The Anthropic API key. Never populated in responses (see
  /// [`GeminiCredentials.gemini_api_key`](#rellm-GeminiCredentials)).
  @$pb.TagNumber(1)
  $core.String get anthropicApiKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set anthropicApiKey($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAnthropicApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnthropicApiKey() => clearField(1);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
