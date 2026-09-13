import { Media, MediaConversion, MediaReference, MediaSize } from "@rellm/api";

// `Media`/`MediaReference` both carry `sizes` now (see `protos/media.proto`'s `Media.sizes` doc) --
// the flat `contentType`/`aspectRatio` fields that used to live directly on each moved into
// per-size entries, so callers need to pick the right `MediaSize` out of the list instead of
// reading a field straight off `media`.
export type MediaRef = Media | MediaReference;

/** The `MediaSize` for a given `conversion`, if `media` has one. */
export function getMediaSize(media: MediaRef, conversion: MediaConversion): MediaSize | undefined {
  return media.sizes.find((size) => size.conversion === conversion);
}

/** The untouched original upload's `MediaSize` -- every `Media`/`MediaReference` this app ever
 * renders should have one (a `url`-only, externally-hosted item, once that's actually populated,
 * would not). */
export function getOriginalSize(media: MediaRef): MediaSize | undefined {
  return getMediaSize(media, MediaConversion.MEDIA_CONVERSION_ORIGINAL);
}

/** The original upload's MIME content type -- replaces the old flat `Media.contentType`/
 * `MediaReference.contentType` fields, now tracked per-size (see `MediaSize`). Empty string if
 * `media` somehow has no original size at all. */
export function getOriginalContentType(media: MediaRef): string {
  return getOriginalSize(media)?.contentType ?? "";
}

/** Whether `media`'s original upload is an image, by its MIME type's top-level part. */
export function isImageMedia(media: MediaRef): boolean {
  return getOriginalContentType(media).startsWith("image/");
}

/** The original upload's aspect ratio (width / height) -- replaces the old flat
 * `MediaReference.aspectRatio` field, now tracked per-size (see `MediaSize`). */
export function getOriginalAspectRatio(media: MediaRef): number | undefined {
  return getOriginalSize(media)?.aspectRatio;
}
