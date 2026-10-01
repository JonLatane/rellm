DROP TABLE media_licenses;
DROP INDEX idx_media_search_text;
ALTER TABLE media DROP COLUMN search_text;
DROP FUNCTION media_build_search_text(VARCHAR, TEXT, JSONB);
DROP INDEX idx_media_visibility_created_at;
DROP INDEX idx_media_content_type_created_at;
ALTER TABLE media DROP COLUMN content_type;
DROP FUNCTION media_original_content_type(JSONB);
