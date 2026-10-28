-- Backs `GetPosts`' FOLLOWING_POSTS listing (`rpcs::posts::get_posts::get_following_posts`).
--
-- That listing joins `follows` (already indexed by `idx_follows (user_id, target_user_id)`) to the
-- top-level posts of each followed author, newest first. The existing posts indexes either lead with
-- `context`/`visibility` (so a per-author lookup can't use them for ordering) or are keyed on
-- `(user_id, context)` with no ordering column, forcing a heap fetch and sort of every post a followed
-- author ever made. This partial index holds exactly the rows the listing considers, keyed by author and
-- then newest-first, so each followed author contributes only their latest posts and the final
-- `ORDER BY sort_published_at DESC LIMIT n` is a bounded top-N.
CREATE INDEX idx_posts_following_feed
    ON posts (user_id, sort_published_at DESC)
    WHERE context = 'POST' AND parent_post_id IS NULL;
