-- Media discovery + licensing:
--   * `media.content_type`: generated copy of the ORIGINAL size's content type (media.sizes is a
--     JSONB array of `{"conversion": 0, ...}` elements), so GetMedia can filter `audio/*` / `video/*`
--     via an index rather than scanning JSONB. `jsonb_path_query_first` (non-`_tz`) is IMMUTABLE,
--     but the wrapper function is declared IMMUTABLE explicitly anyway, mirroring
--     users_build_search_text's approach.
--   * `media.search_text`: weighted tsvector over name/credits/description. See
--     `MediaMetadata` in protos/media.proto for the field importance order.
--   * `media_licenses`: grants for Visibility.LICENSED media.
CREATE FUNCTION media_original_content_type(p_sizes JSONB) RETURNS VARCHAR AS $$
  SELECT jsonb_path_query_first(p_sizes, '$[*] ? (@.conversion == 0).content_type') #>> '{}';
$$ LANGUAGE sql IMMUTABLE;

ALTER TABLE media ADD COLUMN content_type VARCHAR
  GENERATED ALWAYS AS (media_original_content_type(sizes)) STORED;

-- text_pattern_ops makes `content_type LIKE 'audio/%'` index-assisted regardless of DB collation.
CREATE INDEX idx_media_content_type_created_at
  ON media (content_type text_pattern_ops, created_at DESC);
CREATE INDEX idx_media_visibility_created_at ON media (visibility, created_at DESC);

CREATE FUNCTION media_build_search_text(
  p_name VARCHAR,
  p_description TEXT,
  p_metadata JSONB
) RETURNS tsvector AS $$
  SELECT
    setweight(to_tsvector('simple', coalesce(p_name, '') || ' ' ||
      coalesce(p_metadata ->> 'artist', '') || ' ' ||
      coalesce(p_metadata ->> 'director', '')), 'A') ||
    setweight(to_tsvector('simple',
      coalesce(p_metadata ->> 'album', '') || ' ' ||
      coalesce(p_metadata ->> 'composer', '') || ' ' ||
      coalesce(p_metadata ->> 'starring', '') || ' ' ||
      coalesce(p_metadata ->> 'cast', '') || ' ' ||
      coalesce(p_metadata ->> 'narrator', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(p_metadata ->> 'producer', '') || ' ' ||
      coalesce(p_metadata ->> 'crew', '') || ' ' ||
      coalesce(p_metadata ->> 'publisher', '')), 'C') ||
    setweight(to_tsvector('simple', coalesce(p_description, '')), 'D');
$$ LANGUAGE sql IMMUTABLE;

ALTER TABLE media ADD COLUMN search_text tsvector
  GENERATED ALWAYS AS (media_build_search_text(name, description, metadata)) STORED;
CREATE INDEX idx_media_search_text ON media USING GIN (search_text);

CREATE TABLE media_licenses (
  id BIGSERIAL PRIMARY KEY,
  media_id BIGINT NOT NULL REFERENCES media ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMP NULL DEFAULT NULL
);
-- At most one *active* license per (media, user).
CREATE UNIQUE INDEX idx_media_licenses_active ON media_licenses (media_id, user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX idx_media_licenses_user_id ON media_licenses (user_id);
