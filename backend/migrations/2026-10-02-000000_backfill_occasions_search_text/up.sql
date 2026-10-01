-- Rebuilds occasions.search_text (and the denormalized user_id) for every row.
--
-- 2026-09-03-130000_events_use_post_id_as_pk repointed occasions.event_id at events.post_id and
-- fixed the search-text triggers to join the parent Event that way, but never recomputed rows
-- that were already stored: any occasion whose text was built while the trigger joined on the
-- old surrogate events.id (or otherwise couldn't find its parent Event) is missing the parent
-- Event's title/content/author -- e.g. a "Pony Ride" occasion that matches searches for its
-- address but not for "pony". The triggers keep new/edited rows correct; this fixes the rest.
-- Only rows whose text actually changes are written.
UPDATE occasions occ
SET search_text = occasions_build_search_text(
      occasion_post.title, occasion_post.content,
      (SELECT username FROM users WHERE id = occasion_post.user_id),
      (SELECT real_name FROM users WHERE id = occasion_post.user_id),
      occ.location->>'uniformly_formatted_address',
      event_post.title, event_post.content,
      (SELECT username FROM users WHERE id = event_post.user_id),
      (SELECT real_name FROM users WHERE id = event_post.user_id)
    ),
    user_id = occasion_post.user_id
FROM posts occasion_post, events ev, posts event_post
WHERE occ.post_id = occasion_post.id
  AND occ.event_id = ev.post_id
  AND ev.post_id = event_post.id
  AND (
    occ.search_text IS DISTINCT FROM occasions_build_search_text(
      occasion_post.title, occasion_post.content,
      (SELECT username FROM users WHERE id = occasion_post.user_id),
      (SELECT real_name FROM users WHERE id = occasion_post.user_id),
      occ.location->>'uniformly_formatted_address',
      event_post.title, event_post.content,
      (SELECT username FROM users WHERE id = event_post.user_id),
      (SELECT real_name FROM users WHERE id = event_post.user_id)
    )
    OR occ.user_id IS DISTINCT FROM occasion_post.user_id
  );
