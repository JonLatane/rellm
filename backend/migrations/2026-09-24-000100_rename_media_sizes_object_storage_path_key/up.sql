-- Data-only migration renaming the "minio_path" key to "object_storage_path" inside every element
-- of `media.sizes` (the JSONB array introduced by 2026-09-13-000100_restructure_media_sizes).
-- There's no separate `minio_path` *column* on `media` anymore -- only this per-element JSON key,
-- which mirrors `models::media_models::MediaSize`'s Rust field of the same rename (see that
-- migration's doc for the element shape: `{"conversion": 0-3, "minio_path": "...",
-- "content_type": "...", "size_bytes": <bigint>, "aspect_ratio": <float|null>}`).
--
-- `entry - 'minio_path'` drops the old key (jsonb `-` removes a key by text), and
-- `|| jsonb_build_object('object_storage_path', entry -> 'minio_path')` merges in the new one
-- (jsonb `||` merges objects, right-hand side winning on conflicts) -- every other key
-- (`conversion`, `content_type`, `size_bytes`, `aspect_ratio`) passes through untouched. Rows with
-- `sizes IS NULL` or `sizes = '[]'` are left alone (the WHERE guard also means jsonb_agg is never
-- called against zero rows, which would otherwise NULL out the array).
UPDATE media SET sizes = (
  SELECT jsonb_agg(
    entry - 'minio_path' || jsonb_build_object('object_storage_path', entry -> 'minio_path')
  )
  FROM jsonb_array_elements(media.sizes) entry
) WHERE sizes IS NOT NULL AND jsonb_array_length(sizes) > 0;
