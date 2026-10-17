-- A Post may quote (embed) another Post -- see `Post.quoted_post_id` in `protos/posts.proto`.
-- Only valid on `context = 'POST'` posts, enforced by `rpcs::posts::create_post`/`update_post`.
-- Deleting the quoted Post just un-quotes it, rather than deleting (or blocking deletion of) the
-- Posts that quoted it.
ALTER TABLE posts
ADD COLUMN quoted_post_id BIGINT REFERENCES posts (id) ON DELETE SET NULL;

CREATE INDEX posts_quoted_post_id_idx ON posts (quoted_post_id)
WHERE quoted_post_id IS NOT NULL;
