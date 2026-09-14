//
//  Generated code. Do not modify.
//  source: media.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'google/protobuf/timestamp.pb.dart' as $12;
import 'media.pbenum.dart';
import 'permissions.pbenum.dart' as $14;
import 'visibility_moderation.pbenum.dart' as $13;

export 'media.pbenum.dart';

///  A Rellm `Media` message represents a single media item, such as a photo or video.
///  Media data is deliberately *not accessible from the gRPC API*. Instead, the client
///  should fetch media from `http[s]://my.rellm.instance/media/{id}`, unless `url` is set,
///  in which case that URL should be used instead (used for media Rellm doesn't store
///  locally, e.g. from federated ActivityPub/Mastodon or AT Protocol/Bluesky content).
///
///  Media items may be created with a HTTP POST to `http[s]://my.rellm.instance/media`
///  along with an "Authorization" header (your access token) and a "Content-Type" header.
///  On success, the endpoint will return the media ID in plaintext.
///
///  `POST /media` supports the following headers:
///  - `Content-Type` - The MIME content type of the media item.
///  - `Filename` - An optional title for the media item.
///  - `Authorization` - Rellm Access Token for the user. Required, but may be supplied in `Cookies`.
///  - `Cookies` - Standard web cookies. The `rellm_access_token` cookie may be used for authentication.
///
///  `GET /media/{id}` supports the following:
///  - **Headers**:
///      - `Authorization` - Rellm Access Token for the user. May also be supplied in `Cookies` or via query parameter.
///      - `Cookies` - Standard web cookies. The `rellm_access_token` cookie may be used for authentication.
///  - **Query Parameters**:
///      - `authorization` - Rellm Access Token for the user. May also be supplied in the `Cookies` or `Authorization` headers.
///  - Fetching media without authentication requires that it has `GLOBAL_PUBLIC` visibility.
class Media extends $pb.GeneratedMessage {
  factory Media({
    $core.String? id,
    Author? author,
    $core.String? name,
    $core.String? description,
    $13.Visibility? visibility,
    $13.Moderation? moderation,
    $core.bool? generated,
    $core.bool? processed,
    $12.Timestamp? createdAt,
    $12.Timestamp? updatedAt,
    MediaMetadata? metadata,
    $core.String? url,
    $core.Iterable<MediaSize>? sizes,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (author != null) {
      $result.author = author;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (visibility != null) {
      $result.visibility = visibility;
    }
    if (moderation != null) {
      $result.moderation = moderation;
    }
    if (generated != null) {
      $result.generated = generated;
    }
    if (processed != null) {
      $result.processed = processed;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (url != null) {
      $result.url = url;
    }
    if (sizes != null) {
      $result.sizes.addAll(sizes);
    }
    return $result;
  }
  Media._() : super();
  factory Media.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Media.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Media', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<Author>(2, _omitFieldNames ? '' : 'author', subBuilder: Author.create)
    ..aOS(4, _omitFieldNames ? '' : 'name')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..e<$13.Visibility>(6, _omitFieldNames ? '' : 'visibility', $pb.PbFieldType.OE, defaultOrMaker: $13.Visibility.VISIBILITY_UNKNOWN, valueOf: $13.Visibility.valueOf, enumValues: $13.Visibility.values)
    ..e<$13.Moderation>(7, _omitFieldNames ? '' : 'moderation', $pb.PbFieldType.OE, defaultOrMaker: $13.Moderation.MODERATION_UNKNOWN, valueOf: $13.Moderation.valueOf, enumValues: $13.Moderation.values)
    ..aOB(8, _omitFieldNames ? '' : 'generated')
    ..aOB(9, _omitFieldNames ? '' : 'processed')
    ..aOM<$12.Timestamp>(15, _omitFieldNames ? '' : 'createdAt', subBuilder: $12.Timestamp.create)
    ..aOM<$12.Timestamp>(16, _omitFieldNames ? '' : 'updatedAt', subBuilder: $12.Timestamp.create)
    ..aOM<MediaMetadata>(17, _omitFieldNames ? '' : 'metadata', subBuilder: MediaMetadata.create)
    ..aOS(18, _omitFieldNames ? '' : 'url')
    ..pc<MediaSize>(19, _omitFieldNames ? '' : 'sizes', $pb.PbFieldType.PM, subBuilder: MediaSize.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Media clone() => Media()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Media copyWith(void Function(Media) updates) => super.copyWith((message) => updates(message as Media)) as Media;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Media create() => Media._();
  Media createEmptyInstance() => create();
  static $pb.PbList<Media> createRepeated() => $pb.PbList<Media>();
  @$core.pragma('dart2js:noInline')
  static Media getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Media>(create);
  static Media? _defaultInstance;

  /// The ID of the media item.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// The user who created the media item.
  @$pb.TagNumber(2)
  Author get author => $_getN(1);
  @$pb.TagNumber(2)
  set author(Author v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAuthor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthor() => clearField(2);
  @$pb.TagNumber(2)
  Author ensureAuthor() => $_ensure(1);

  /// An optional title for the media item.
  @$pb.TagNumber(4)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(4)
  set name($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(4)
  void clearName() => clearField(4);

  /// An optional description for the media item.
  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);

  /// Visibility of the media item.
  @$pb.TagNumber(6)
  $13.Visibility get visibility => $_getN(4);
  @$pb.TagNumber(6)
  set visibility($13.Visibility v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasVisibility() => $_has(4);
  @$pb.TagNumber(6)
  void clearVisibility() => clearField(6);

  /// Moderation of the media item.
  @$pb.TagNumber(7)
  $13.Moderation get moderation => $_getN(5);
  @$pb.TagNumber(7)
  set moderation($13.Moderation v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasModeration() => $_has(5);
  @$pb.TagNumber(7)
  void clearModeration() => clearField(7);

  /// Indicates the media was generated by the server rather than uploaded manually by a user.
  @$pb.TagNumber(8)
  $core.bool get generated => $_getBF(6);
  @$pb.TagNumber(8)
  set generated($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(8)
  $core.bool hasGenerated() => $_has(6);
  @$pb.TagNumber(8)
  void clearGenerated() => clearField(8);

  /// Media is generally stored as-is on upload.
  /// When background jobs process and compress the media, this flag is set to true.
  @$pb.TagNumber(9)
  $core.bool get processed => $_getBF(7);
  @$pb.TagNumber(9)
  set processed($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(9)
  $core.bool hasProcessed() => $_has(7);
  @$pb.TagNumber(9)
  void clearProcessed() => clearField(9);

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

  @$pb.TagNumber(17)
  MediaMetadata get metadata => $_getN(10);
  @$pb.TagNumber(17)
  set metadata(MediaMetadata v) { setField(17, v); }
  @$pb.TagNumber(17)
  $core.bool hasMetadata() => $_has(10);
  @$pb.TagNumber(17)
  void clearMetadata() => clearField(17);
  @$pb.TagNumber(17)
  MediaMetadata ensureMetadata() => $_ensure(10);

  /// An external URL to fetch the media from, in lieu of `/media/{id}`. Used for representing
  /// media owned by other protocols/servers (e.g. ActivityPub/Mastodon, AT Protocol/Bluesky)
  /// that Rellm does not store locally. If unset, clients fall back to `/media/{id}`.
  @$pb.TagNumber(18)
  $core.String get url => $_getSZ(11);
  @$pb.TagNumber(18)
  set url($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(18)
  $core.bool hasUrl() => $_has(11);
  @$pb.TagNumber(18)
  void clearUrl() => clearField(18);

  /// Every stored copy of this media item's bytes -- the original upload
  /// (`MEDIA_CONVERSION_ORIGINAL`) plus any auto-generated resized copies (see
  /// `convert_media_sizes`'s background job) -- each with its own content type, byte size, and
  /// (once known) aspect ratio. Always has at least one `MEDIA_CONVERSION_ORIGINAL` entry unless
  /// `url` is set (externally-hosted media has no locally-stored copies at all). The original is
  /// tracked here rather than as a separate top-level field so it can eventually be deleted to
  /// free space once converted copies exist, while remaining fully accounted for by
  /// `User.media_storage_bytes_used` up until that point.
  @$pb.TagNumber(19)
  $core.List<MediaSize> get sizes => $_getList(12);
}

/// One stored copy of a `Media` item's bytes -- either its untouched original upload
/// (`MEDIA_CONVERSION_ORIGINAL`) or an auto-generated resized copy, as produced by the
/// `convert_media_sizes` background job. Fields are tracked per-size (rather than once on `Media`
/// itself) so that a future conversion producing a different kind of derived copy -- e.g. a
/// `image/jpeg` poster frame for a `video/mp4` original, or a differently-cropped aspect ratio --
/// can vary any of them independently of the original.
class MediaSize extends $pb.GeneratedMessage {
  factory MediaSize({
    MediaConversion? conversion,
    $fixnum.Int64? sizeBytes,
    $core.double? aspectRatio,
    $core.String? contentType,
  }) {
    final $result = create();
    if (conversion != null) {
      $result.conversion = conversion;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (aspectRatio != null) {
      $result.aspectRatio = aspectRatio;
    }
    if (contentType != null) {
      $result.contentType = contentType;
    }
    return $result;
  }
  MediaSize._() : super();
  factory MediaSize.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaSize.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaSize', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..e<MediaConversion>(1, _omitFieldNames ? '' : 'conversion', $pb.PbFieldType.OE, defaultOrMaker: MediaConversion.MEDIA_CONVERSION_ORIGINAL, valueOf: MediaConversion.valueOf, enumValues: MediaConversion.values)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'sizeBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'aspectRatio', $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'contentType')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaSize clone() => MediaSize()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaSize copyWith(void Function(MediaSize) updates) => super.copyWith((message) => updates(message as MediaSize)) as MediaSize;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaSize create() => MediaSize._();
  MediaSize createEmptyInstance() => create();
  static $pb.PbList<MediaSize> createRepeated() => $pb.PbList<MediaSize>();
  @$core.pragma('dart2js:noInline')
  static MediaSize getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaSize>(create);
  static MediaSize? _defaultInstance;

  /// Which copy this is -- the untouched original, or one of the auto-generated resized copies.
  @$pb.TagNumber(1)
  MediaConversion get conversion => $_getN(0);
  @$pb.TagNumber(1)
  set conversion(MediaConversion v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasConversion() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversion() => clearField(1);

  /// This copy's size on disk/in MinIO, in bytes. Summed (across every size, of every Media a user
  /// owns) into `User.media_storage_bytes_used`.
  @$pb.TagNumber(2)
  $fixnum.Int64 get sizeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSizeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearSizeBytes() => clearField(2);

  /// Width divided by height. Set by the `convert_media_sizes` background job once it's able to
  /// read the media's dimensions (via ImageMagick/ffprobe); unset until then.
  @$pb.TagNumber(3)
  $core.double get aspectRatio => $_getN(2);
  @$pb.TagNumber(3)
  set aspectRatio($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAspectRatio() => $_has(2);
  @$pb.TagNumber(3)
  void clearAspectRatio() => clearField(3);

  /// The MIME content type of this copy specifically. Usually identical across every size of a
  /// given `Media`, but not guaranteed to be -- e.g. a future video-thumbnail conversion could
  /// produce an `image/jpeg` size for a `video/mp4` original.
  @$pb.TagNumber(4)
  $core.String get contentType => $_getSZ(3);
  @$pb.TagNumber(4)
  set contentType($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasContentType() => $_has(3);
  @$pb.TagNumber(4)
  void clearContentType() => clearField(4);
}

/// Free-form metadata about a [`Media`](#rellm-Media) item that isn't queried/filtered on, so doesn't need its
/// own columns.
class MediaMetadata extends $pb.GeneratedMessage {
  factory MediaMetadata({
    $fixnum.Int64? videoPreviewTimeMs,
  }) {
    final $result = create();
    if (videoPreviewTimeMs != null) {
      $result.videoPreviewTimeMs = videoPreviewTimeMs;
    }
    return $result;
  }
  MediaMetadata._() : super();
  factory MediaMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'videoPreviewTimeMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaMetadata clone() => MediaMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaMetadata copyWith(void Function(MediaMetadata) updates) => super.copyWith((message) => updates(message as MediaMetadata)) as MediaMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaMetadata create() => MediaMetadata._();
  MediaMetadata createEmptyInstance() => create();
  static $pb.PbList<MediaMetadata> createRepeated() => $pb.PbList<MediaMetadata>();
  @$core.pragma('dart2js:noInline')
  static MediaMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaMetadata>(create);
  static MediaMetadata? _defaultInstance;

  /// For video media, how far into the video (in milliseconds) its preview/poster frame should be
  /// taken from -- both via a `#t=<seconds>` Media Fragments URI on the `<video>` element's `src`,
  /// and as the timestamp `ffmpeg` seeks to when generating the `VIDEO_PREVIEW_THUMBNAIL_*` poster
  /// frames (see `MediaConversion`). Unset defaults to 1s (1000 in ms), or if the video is shorter
  /// than 1.5s, the midpoint of the video. Settable via `UpdateMedia`; changing it invalidates
  /// (deletes) any existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes, so the `convert_media_sizes`
  /// background job regenerates them at the new time.
  @$pb.TagNumber(1)
  $fixnum.Int64 get videoPreviewTimeMs => $_getI64(0);
  @$pb.TagNumber(1)
  set videoPreviewTimeMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVideoPreviewTimeMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearVideoPreviewTimeMs() => clearField(1);
}

/// A reference to a media item, designed to be included in other messages as a reference.
/// Contains the bare minimum data needed to fetch media via the HTTP API and render it,
/// and the media item's name (for alt text usage).
class MediaReference extends $pb.GeneratedMessage {
  factory MediaReference({
    $core.String? id,
    $core.String? name,
    $core.bool? generated,
    MediaMetadata? metadata,
    $core.Iterable<MediaSize>? sizes,
    $core.String? url,
    $core.String? description,
    Author? author,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (generated != null) {
      $result.generated = generated;
    }
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (sizes != null) {
      $result.sizes.addAll(sizes);
    }
    if (url != null) {
      $result.url = url;
    }
    if (description != null) {
      $result.description = description;
    }
    if (author != null) {
      $result.author = author;
    }
    return $result;
  }
  MediaReference._() : super();
  factory MediaReference.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaReference.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaReference', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOB(4, _omitFieldNames ? '' : 'generated')
    ..aOM<MediaMetadata>(5, _omitFieldNames ? '' : 'metadata', subBuilder: MediaMetadata.create)
    ..pc<MediaSize>(6, _omitFieldNames ? '' : 'sizes', $pb.PbFieldType.PM, subBuilder: MediaSize.create)
    ..aOS(11, _omitFieldNames ? '' : 'url')
    ..aOS(12, _omitFieldNames ? '' : 'description')
    ..aOM<Author>(13, _omitFieldNames ? '' : 'author', subBuilder: Author.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaReference clone() => MediaReference()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaReference copyWith(void Function(MediaReference) updates) => super.copyWith((message) => updates(message as MediaReference)) as MediaReference;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaReference create() => MediaReference._();
  MediaReference createEmptyInstance() => create();
  static $pb.PbList<MediaReference> createRepeated() => $pb.PbList<MediaReference>();
  @$core.pragma('dart2js:noInline')
  static MediaReference getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaReference>(create);
  static MediaReference? _defaultInstance;

  /// The ID of the media item.
  @$pb.TagNumber(2)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(2)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(2)
  void clearId() => clearField(2);

  /// An optional title for the media item.
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(3)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(3)
  void clearName() => clearField(3);

  /// Indicates the media was generated by the server rather than uploaded manually by a user.
  @$pb.TagNumber(4)
  $core.bool get generated => $_getBF(2);
  @$pb.TagNumber(4)
  set generated($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasGenerated() => $_has(2);
  @$pb.TagNumber(4)
  void clearGenerated() => clearField(4);

  @$pb.TagNumber(5)
  MediaMetadata get metadata => $_getN(3);
  @$pb.TagNumber(5)
  set metadata(MediaMetadata v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasMetadata() => $_has(3);
  @$pb.TagNumber(5)
  void clearMetadata() => clearField(5);
  @$pb.TagNumber(5)
  MediaMetadata ensureMetadata() => $_ensure(3);

  /// See `Media.sizes`.
  @$pb.TagNumber(6)
  $core.List<MediaSize> get sizes => $_getList(4);

  /// An external URL to fetch the media from, in lieu of `/media/{id}`. See `Media.url`.
  /// If unset, clients fall back to `/media/{id}`.
  @$pb.TagNumber(11)
  $core.String get url => $_getSZ(5);
  @$pb.TagNumber(11)
  set url($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(11)
  $core.bool hasUrl() => $_has(5);
  @$pb.TagNumber(11)
  void clearUrl() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get description => $_getSZ(6);
  @$pb.TagNumber(12)
  set description($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(12)
  $core.bool hasDescription() => $_has(6);
  @$pb.TagNumber(12)
  void clearDescription() => clearField(12);

  /// The user who created the media item. See `Media.author`. Included here (unlike most other
  /// `MediaReference` fields, which are deliberately pared down from `Media`) so clients that only
  /// ever see a `MediaReference` -- e.g. a `Post.media` item -- can still tell whether the current
  /// viewer owns it, without a separate `Media` lookup.
  @$pb.TagNumber(13)
  Author get author => $_getN(7);
  @$pb.TagNumber(13)
  set author(Author v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasAuthor() => $_has(7);
  @$pb.TagNumber(13)
  void clearAuthor() => clearField(13);
  @$pb.TagNumber(13)
  Author ensureAuthor() => $_ensure(7);
}

///  Post/authorship-centric version of User. UI can cross-reference user details from its own
///  cache (for things like admin/bot icons).
///
///  Lives in `media.proto` (rather than `users.proto`, where it used to live, or its own
///  `authors.proto`, split out from `users.proto` for a time) because `Author.avatar` needs
///  `MediaReference` and `Media`/`MediaReference` need `Author` (see this field's own doc) --
///  mutually recursive types belong in the same file, since `protoc` rejects circular *file*
///  imports even though the recursive *types* themselves are perfectly valid. `users.proto`
///  (`User.sync_destinations`) and `sync.proto` (`SyncDestination.owner`, `SyncSource.owner`) both
///  depend on this without depending on each other, via their own `import "media.proto"` (both
///  already needed it anyway, for `User.avatar`/`Media`-shaped fields).
class Author extends $pb.GeneratedMessage {
  factory Author({
    $core.String? userId,
    $core.String? username,
    MediaReference? avatar,
    $core.String? realName,
    $core.Iterable<$14.Permission>? permissions,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (username != null) {
      $result.username = username;
    }
    if (avatar != null) {
      $result.avatar = avatar;
    }
    if (realName != null) {
      $result.realName = realName;
    }
    if (permissions != null) {
      $result.permissions.addAll(permissions);
    }
    return $result;
  }
  Author._() : super();
  factory Author.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Author.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Author', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOM<MediaReference>(3, _omitFieldNames ? '' : 'avatar', subBuilder: MediaReference.create)
    ..aOS(4, _omitFieldNames ? '' : 'realName')
    ..pc<$14.Permission>(5, _omitFieldNames ? '' : 'permissions', $pb.PbFieldType.KE, valueOf: $14.Permission.valueOf, enumValues: $14.Permission.values, defaultEnumValue: $14.Permission.PERMISSION_UNKNOWN)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Author clone() => Author()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Author copyWith(void Function(Author) updates) => super.copyWith((message) => updates(message as Author)) as Author;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Author create() => Author._();
  Author createEmptyInstance() => create();
  static $pb.PbList<Author> createRepeated() => $pb.PbList<Author>();
  @$core.pragma('dart2js:noInline')
  static Author getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Author>(create);
  static Author? _defaultInstance;

  /// Permanent string ID for the user. Will never contain a `@` symbol.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  /// Impermanent string username for the user. Will never contain a `@` symbol.
  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  /// The user's avatar.
  @$pb.TagNumber(3)
  MediaReference get avatar => $_getN(2);
  @$pb.TagNumber(3)
  set avatar(MediaReference v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasAvatar() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvatar() => clearField(3);
  @$pb.TagNumber(3)
  MediaReference ensureAvatar() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get realName => $_getSZ(3);
  @$pb.TagNumber(4)
  set realName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRealName() => $_has(3);
  @$pb.TagNumber(4)
  void clearRealName() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$14.Permission> get permissions => $_getList(4);
}

/// Valid GetMediaRequest formats:
/// - `{user_id: abc123}` - Gets the media of the given user that the current user can see. IE:
///     - *all* of the current user's own media
///     - `GLOBAL_PUBLIC` media for the user if the current user is not logged in.
///     - `SERVER_PUBLIC` media for the user if the current user is logged in.
///     - `LIMITED` media for the user if the current user is following the user.
/// - `{media_id: abc123}` - Gets the media with the given ID, if visible to the current user.
class GetMediaRequest extends $pb.GeneratedMessage {
  factory GetMediaRequest({
    $core.String? mediaId,
    $core.String? userId,
    $core.int? page,
  }) {
    final $result = create();
    if (mediaId != null) {
      $result.mediaId = mediaId;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (page != null) {
      $result.page = page;
    }
    return $result;
  }
  GetMediaRequest._() : super();
  factory GetMediaRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMediaRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMediaRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mediaId')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'page', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMediaRequest clone() => GetMediaRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMediaRequest copyWith(void Function(GetMediaRequest) updates) => super.copyWith((message) => updates(message as GetMediaRequest)) as GetMediaRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMediaRequest create() => GetMediaRequest._();
  GetMediaRequest createEmptyInstance() => create();
  static $pb.PbList<GetMediaRequest> createRepeated() => $pb.PbList<GetMediaRequest>();
  @$core.pragma('dart2js:noInline')
  static GetMediaRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMediaRequest>(create);
  static GetMediaRequest? _defaultInstance;

  /// Returns the single media item with the given ID.
  @$pb.TagNumber(1)
  $core.String get mediaId => $_getSZ(0);
  @$pb.TagNumber(1)
  set mediaId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMediaId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMediaId() => clearField(1);

  /// Returns all media items for the given user.
  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);

  @$pb.TagNumber(11)
  $core.int get page => $_getIZ(2);
  @$pb.TagNumber(11)
  set page($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(11)
  $core.bool hasPage() => $_has(2);
  @$pb.TagNumber(11)
  void clearPage() => clearField(11);
}

class GetMediaResponse extends $pb.GeneratedMessage {
  factory GetMediaResponse({
    $core.Iterable<Media>? media,
    $core.bool? hasNextPage,
  }) {
    final $result = create();
    if (media != null) {
      $result.media.addAll(media);
    }
    if (hasNextPage != null) {
      $result.hasNextPage = hasNextPage;
    }
    return $result;
  }
  GetMediaResponse._() : super();
  factory GetMediaResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetMediaResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GetMediaResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..pc<Media>(1, _omitFieldNames ? '' : 'media', $pb.PbFieldType.PM, subBuilder: Media.create)
    ..aOB(2, _omitFieldNames ? '' : 'hasNextPage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetMediaResponse clone() => GetMediaResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetMediaResponse copyWith(void Function(GetMediaResponse) updates) => super.copyWith((message) => updates(message as GetMediaResponse)) as GetMediaResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMediaResponse create() => GetMediaResponse._();
  GetMediaResponse createEmptyInstance() => create();
  static $pb.PbList<GetMediaResponse> createRepeated() => $pb.PbList<GetMediaResponse>();
  @$core.pragma('dart2js:noInline')
  static GetMediaResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetMediaResponse>(create);
  static GetMediaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<Media> get media => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get hasNextPage => $_getBF(1);
  @$pb.TagNumber(2)
  set hasNextPage($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHasNextPage() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasNextPage() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
