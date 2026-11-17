-- The per-namespace vector search service keeps an in-memory index of every embedding and catches up with new
-- and re-embedded rows by reading `(embedded_at, id)` in order past its last position. These make that read an
-- index range scan instead of a sort of the whole table.
CREATE INDEX idx_post_embeddings_embedded_at ON post_embeddings (embedded_at, post_id);
CREATE INDEX idx_event_embeddings_embedded_at ON event_embeddings (embedded_at, event_id);
CREATE INDEX idx_media_embeddings_embedded_at ON media_embeddings (embedded_at, media_id);
CREATE INDEX idx_user_profile_embeddings_embedded_at ON user_profile_embeddings (embedded_at, user_id);
