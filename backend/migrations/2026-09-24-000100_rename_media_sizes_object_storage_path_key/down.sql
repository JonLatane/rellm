-- Mirror-image of up.sql: renames "object_storage_path" back to "minio_path" inside every
-- element of `media.sizes`.
UPDATE media SET sizes = (
  SELECT jsonb_agg(
    entry - 'object_storage_path' || jsonb_build_object('minio_path', entry -> 'object_storage_path')
  )
  FROM jsonb_array_elements(media.sizes) entry
) WHERE sizes IS NOT NULL AND jsonb_array_length(sizes) > 0;
