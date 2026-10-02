-- Failed link-preview generation attempts per post (see `generate_link_preview_images`), so a post
-- whose capture always fails stops being retried every run (and crowding out others in the job's
-- `LIMIT`ed batch) once it hits the attempt cap. Rows are removed on success or when previews are
-- deleted/regenerated.
CREATE TABLE link_preview_attempts (
  post_id BIGINT PRIMARY KEY REFERENCES posts (id) ON DELETE CASCADE,
  attempts INT NOT NULL DEFAULT 0,
  last_attempt_at TIMESTAMP NOT NULL DEFAULT now()
);
