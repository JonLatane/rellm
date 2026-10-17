DROP INDEX IF EXISTS posts_quoted_post_id_idx;
ALTER TABLE posts DROP COLUMN quoted_post_id;
