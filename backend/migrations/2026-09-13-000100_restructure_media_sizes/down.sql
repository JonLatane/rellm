DROP INDEX IF EXISTS idx_media_sizes_gin;
DROP INDEX IF EXISTS idx_media_user_id_created_at;

ALTER TABLE media ADD COLUMN minio_path VARCHAR;
ALTER TABLE media ADD COLUMN content_type VARCHAR;
ALTER TABLE media ADD COLUMN aspect_ratio REAL;
ALTER TABLE media ADD COLUMN converted_sizes JSONB NOT NULL DEFAULT '{}';

-- Best-effort reverse of up.sql: byte counts (never tracked pre-restructure) are simply dropped.
UPDATE media SET
  minio_path = (
    SELECT entry ->> 'minio_path' FROM jsonb_array_elements(media.sizes) entry
    WHERE (entry ->> 'conversion')::int = 0 LIMIT 1
  ),
  content_type = (
    SELECT entry ->> 'content_type' FROM jsonb_array_elements(media.sizes) entry
    WHERE (entry ->> 'conversion')::int = 0 LIMIT 1
  ),
  aspect_ratio = (
    SELECT (entry ->> 'aspect_ratio')::real FROM jsonb_array_elements(media.sizes) entry
    WHERE (entry ->> 'conversion')::int = 0 LIMIT 1
  ),
  converted_sizes = (
    SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) FROM (
      SELECT
        CASE (entry ->> 'conversion')::int
          WHEN 1 THEN 'small' WHEN 2 THEN 'medium' WHEN 3 THEN 'large'
        END AS key,
        jsonb_build_object('minio_path', entry ->> 'minio_path', 'content_type', entry ->> 'content_type') AS value
      FROM jsonb_array_elements(media.sizes) entry
      WHERE (entry ->> 'conversion')::int IN (1, 2, 3)
    ) sub
  );

ALTER TABLE media ALTER COLUMN minio_path SET NOT NULL;
ALTER TABLE media ALTER COLUMN content_type SET NOT NULL;

ALTER TABLE media DROP COLUMN sizes;
