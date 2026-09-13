-- Restructures Media's stored-copy tracking from two separate places (minio_path/content_type
-- columns for the original upload, plus a converted_sizes JSON *object* keyed by "small"/
-- "medium"/"large" for the auto-generated resized copies) into one `sizes` JSONB *array* covering
-- every stored copy -- including the original -- uniformly. Each element is
-- `{"conversion": 0-3, "minio_path": "...", "content_type": "...", "size_bytes": <bigint>,
-- "aspect_ratio": <float|null>}` (see models::media_models::MediaSize; "minio_path" is
-- server-internal and deliberately absent from the wire proto MediaSize). `conversion` mirrors
-- protos::MediaConversion's discriminants: 0=ORIGINAL, 1=SMALL, 2=MEDIUM, 3=LARGE.
--
-- size_bytes is unknown for existing rows -- no prior code ever recorded a byte count anywhere,
-- for the original or any converted size -- so it's populated here as a 0 placeholder, then
-- backfilled with real byte counts (via a MinIO stat per entry) by a background task main.rs
-- spawns on every server startup. That backfill is idempotent: it only ever processes rows still
-- holding a 0 placeholder, found via idx_media_sizes_gin below, so a restart after it completes
-- finds nothing left to do.
ALTER TABLE media ADD COLUMN sizes JSONB;

UPDATE media SET sizes = (
  SELECT jsonb_agg(entry) FROM (
    SELECT jsonb_build_object(
      'conversion', 0,
      'minio_path', media.minio_path,
      'content_type', media.content_type,
      'size_bytes', 0,
      'aspect_ratio', media.aspect_ratio
    ) AS entry
    UNION ALL
    SELECT jsonb_build_object(
      'conversion', 1,
      'minio_path', media.converted_sizes -> 'small' ->> 'minio_path',
      'content_type', media.converted_sizes -> 'small' ->> 'content_type',
      'size_bytes', 0,
      'aspect_ratio', media.aspect_ratio
    ) WHERE media.converted_sizes ? 'small'
    UNION ALL
    SELECT jsonb_build_object(
      'conversion', 2,
      'minio_path', media.converted_sizes -> 'medium' ->> 'minio_path',
      'content_type', media.converted_sizes -> 'medium' ->> 'content_type',
      'size_bytes', 0,
      'aspect_ratio', media.aspect_ratio
    ) WHERE media.converted_sizes ? 'medium'
    UNION ALL
    SELECT jsonb_build_object(
      'conversion', 3,
      'minio_path', media.converted_sizes -> 'large' ->> 'minio_path',
      'content_type', media.converted_sizes -> 'large' ->> 'content_type',
      'size_bytes', 0,
      'aspect_ratio', media.aspect_ratio
    ) WHERE media.converted_sizes ? 'large'
  ) entries
);

ALTER TABLE media ALTER COLUMN sizes SET NOT NULL;
ALTER TABLE media ALTER COLUMN sizes SET DEFAULT '[]';

ALTER TABLE media DROP COLUMN minio_path;
ALTER TABLE media DROP COLUMN content_type;
ALTER TABLE media DROP COLUMN converted_sizes;
ALTER TABLE media DROP COLUMN aspect_ratio;

-- Speeds up both the pre-existing get_user_media query (filter+order by user_id/created_at,
-- unindexed until now) and the new per-user byte-sum query
-- (logic::user_counts::media_storage_bytes_used) filtering by user_id.
CREATE INDEX idx_media_user_id_created_at ON media (user_id, created_at);
-- GIN containment index on the sizes array itself -- makes the startup backfill's "any row with a
-- still-zero size_bytes entry" lookup (`sizes @> '[{"size_bytes": 0}]'`) an index scan instead of
-- a sequential scan of the whole table, on every restart until the backfill fully completes.
CREATE INDEX idx_media_sizes_gin ON media USING GIN (sizes jsonb_path_ops);
