DROP INDEX idx_users_created_at;

ALTER TABLE server_configurations DROP COLUMN search_settings;

DROP TABLE user_profile_embeddings;
DROP TABLE media_embeddings;
DROP TABLE event_embeddings;
DROP TABLE post_embeddings;

DROP FUNCTION event_search_document(BIGINT);
DROP FUNCTION visibility_openness(VARCHAR);
DROP FUNCTION media_search_document(BIGINT);
DROP FUNCTION user_search_document(BIGINT);
DROP FUNCTION post_search_document(BIGINT);

-- Restore the original inline definitions.
CREATE OR REPLACE FUNCTION posts_build_search_text(
  p_title VARCHAR, p_link VARCHAR, p_content TEXT, p_username VARCHAR, p_real_name VARCHAR
) RETURNS tsvector AS $$
  SELECT
    setweight(to_tsvector('simple', coalesce(p_username, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(p_title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(p_real_name, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(p_content, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(p_link, '')), 'D');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION users_build_search_text(
  p_username VARCHAR, p_real_name VARCHAR, p_bio TEXT
) RETURNS tsvector AS $$
  SELECT
    setweight(to_tsvector('simple', coalesce(p_username, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(p_real_name, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(p_bio, '')), 'C');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION media_build_search_text(
  p_name VARCHAR, p_description TEXT, p_metadata JSONB
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

DROP FUNCTION media_search_fields(VARCHAR, TEXT, JSONB);
DROP FUNCTION users_search_fields(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION posts_search_fields(VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION search_fields_to_document(TEXT[]);
DROP FUNCTION search_fields_to_tsvector(TEXT[]);
