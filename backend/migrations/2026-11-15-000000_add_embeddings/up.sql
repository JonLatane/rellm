-- Semantic search: one definition of "the searchable text", embeddings of it, and the setting that
-- turns embeddings on.
--
-- 1. SEARCH FIELDS. Postgres full-text search and the embeddings must index *the same text* (it was
--    already duplicated: each `*_build_search_text` listed its own fields and weights inline).
--    `<entity>_search_fields(...)` now lists an entity's searchable text once, as a 4-element
--    TEXT[] -- index 1..4 = weight A..D, most important first. Two generic functions derive
--    everything else from that array:
--      * `search_fields_to_tsvector` -> what the GIN-indexed `search_text` columns hold
--      * `search_fields_to_document` -> the plain text the embedding job feeds to the model
--    The existing `*_build_search_text` functions keep their names/signatures (triggers, generated
--    columns and the occasions builder call them) and now just compose the two. They index the
--    same lexemes as before, so stored `search_text` values stay valid and are not rewritten.
--    `occasions_build_search_text` is left alone: it merges two Posts' fields per Occasion, which
--    is search-index plumbing with no embedding counterpart (Events embed via
--    `event_search_document` below).
CREATE FUNCTION search_fields_to_tsvector(p_fields TEXT[]) RETURNS tsvector AS $$
  SELECT
    setweight(to_tsvector('simple', coalesce(p_fields[1], '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(p_fields[2], '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(p_fields[3], '')), 'C') ||
    setweight(to_tsvector('simple', coalesce(p_fields[4], '')), 'D');
$$ LANGUAGE sql IMMUTABLE;

-- Non-empty tiers joined by newlines, most important first (embedding models truncate long input
-- from the end). '' when there's nothing to index.
CREATE FUNCTION search_fields_to_document(p_fields TEXT[]) RETURNS TEXT AS $$
  SELECT coalesce(btrim(concat_ws(E'\n',
    nullif(btrim(p_fields[1]), ''),
    nullif(btrim(p_fields[2]), ''),
    nullif(btrim(p_fields[3]), ''),
    nullif(btrim(p_fields[4]), '')
  )), '');
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION posts_search_fields(
  p_title VARCHAR,
  p_link VARCHAR,
  p_content TEXT,
  p_username VARCHAR,
  p_real_name VARCHAR
) RETURNS TEXT[] AS $$
  SELECT ARRAY[
    concat_ws(E'\n', p_title, p_username),
    concat_ws(E'\n', p_content, p_real_name),
    NULL,
    p_link
  ];
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION users_search_fields(
  p_username VARCHAR,
  p_real_name VARCHAR,
  p_bio TEXT
) RETURNS TEXT[] AS $$
  SELECT ARRAY[p_username, p_real_name, p_bio, NULL];
$$ LANGUAGE sql IMMUTABLE;

-- Weighting mirrors `MediaMetadata` in protos/media.proto (see media_build_search_text's original
-- migration, 2026-10-01-000000_media_search_licenses_credits).
CREATE FUNCTION media_search_fields(
  p_name VARCHAR,
  p_description TEXT,
  p_metadata JSONB
) RETURNS TEXT[] AS $$
  SELECT ARRAY[
    concat_ws(E'\n', p_name, p_metadata ->> 'artist', p_metadata ->> 'director'),
    concat_ws(E'\n', p_metadata ->> 'album', p_metadata ->> 'composer', p_metadata ->> 'starring',
      p_metadata ->> 'cast', p_metadata ->> 'narrator'),
    concat_ws(E'\n', p_metadata ->> 'producer', p_metadata ->> 'crew', p_metadata ->> 'publisher'),
    p_description
  ];
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION posts_build_search_text(
  p_title VARCHAR, p_link VARCHAR, p_content TEXT, p_username VARCHAR, p_real_name VARCHAR
) RETURNS tsvector AS $$
  SELECT search_fields_to_tsvector(posts_search_fields(p_title, p_link, p_content, p_username, p_real_name));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION users_build_search_text(
  p_username VARCHAR, p_real_name VARCHAR, p_bio TEXT
) RETURNS tsvector AS $$
  SELECT search_fields_to_tsvector(users_search_fields(p_username, p_real_name, p_bio));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION media_build_search_text(
  p_name VARCHAR, p_description TEXT, p_metadata JSONB
) RETURNS tsvector AS $$
  SELECT search_fields_to_tsvector(media_search_fields(p_name, p_description, p_metadata));
$$ LANGUAGE sql IMMUTABLE;

-- 2. SEARCH DOCUMENTS: the text each embedding is generated from, by row id. STABLE (they read
--    other tables), so they can't back an index -- the embedding job calls them directly.
CREATE FUNCTION post_search_document(p_post_id BIGINT) RETURNS TEXT AS $$
  SELECT search_fields_to_document(
    posts_search_fields(p.title, p.link, p.content, u.username, u.real_name))
  FROM posts p LEFT JOIN users u ON u.id = p.user_id
  WHERE p.id = p_post_id;
$$ LANGUAGE sql STABLE;

CREATE FUNCTION user_search_document(p_user_id BIGINT) RETURNS TEXT AS $$
  SELECT search_fields_to_document(users_search_fields(u.username, u.real_name, u.bio))
  FROM users u WHERE u.id = p_user_id;
$$ LANGUAGE sql STABLE;

CREATE FUNCTION media_search_document(p_media_id BIGINT) RETURNS TEXT AS $$
  SELECT search_fields_to_document(media_search_fields(m.name, m.description, m.metadata))
  FROM media m WHERE m.id = p_media_id;
$$ LANGUAGE sql STABLE;

-- An Event's document is its Post's document plus what only the Event has: when and where its
-- Occasions are (soonest first, at most 10) and each Occasion's own title.
--
-- One embedding is shared by everyone who can see the Event, but each Occasion has its own Post with
-- its own visibility/moderation -- so only Occasions anyone who can see the Event could also see
-- are included: moderation passing (UNMODERATED/APPROVED) and visibility at least as public as the
-- Event's own Post. A private or pending Occasion's title/address never influences who a search
-- returns. An Event that hides its location until RSVP approval
-- (EventInfo.hide_location_until_rsvp_approved) doesn't leak it here either.
CREATE FUNCTION visibility_openness(p_visibility VARCHAR) RETURNS INT AS $$
  SELECT CASE p_visibility
    WHEN 'GLOBAL_PUBLIC' THEN 3
    WHEN 'SERVER_PUBLIC' THEN 2
    WHEN 'LIMITED' THEN 1
    ELSE 0 END;
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION event_search_document(p_event_id BIGINT) RETURNS TEXT AS $$
  SELECT concat_ws(E'\n',
    nullif(post_search_document(p_event_id), ''),
    (SELECT string_agg(line, E'\n' ORDER BY starts_at) FROM (
       SELECT o.starts_at,
         concat_ws(' - ',
           nullif(btrim(op.title), ''),
           to_char(o.starts_at, 'FMDay, FMMonth FMDD, YYYY'),
           CASE WHEN coalesce((e.info ->> 'hide_location_until_rsvp_approved')::boolean, false)
                THEN NULL
                ELSE nullif(btrim(o.location ->> 'uniformly_formatted_address'), '') END
         ) AS line
       FROM occasions o
       JOIN posts op ON op.id = o.post_id
       WHERE o.event_id = p_event_id
         AND op.moderation IN ('UNMODERATED', 'APPROVED')
         AND visibility_openness(op.visibility) >= visibility_openness(ep.visibility)
       ORDER BY o.starts_at
       LIMIT 10
     ) occ)
  )
  FROM events e JOIN posts ep ON ep.id = e.post_id
  WHERE e.post_id = p_event_id;
$$ LANGUAGE sql STABLE;

-- 3. EMBEDDINGS. One table per kind of thing searched (Posts and Events both have a Post as their
-- source, but an Event's embedding also covers its Occasions -- see event_search_document).
--   embedding    f32 little-endian bytes (dimension = model's); NULL = the document is empty, so
--                there's nothing to embed (the row still records that, so it isn't retried forever).
--   document_hash 64-bit hash (`hashtextextended(document, 0)`) of the document that was embedded;
--                the job re-embeds when it changes (author renamed, post edited, ...) or when
--                `model` isn't the current model. A hash rather than the text keeps rows small; a
--                collision (~2^-64) would only skip one re-embed. Should a Postgres upgrade ever
--                change the hash function, the effect is one harmless round of re-embedding.
--   checked_at   last time the job compared document_hash -- the staleness sweep goes oldest-first.
-- No pgvector: self-hosted Postgres installs can't be assumed to have the extension, so vectors are
-- plain bytea and similarity is computed in the server (see logic::embeddings).
CREATE TABLE post_embeddings (
  post_id BIGINT PRIMARY KEY REFERENCES posts ON DELETE CASCADE,
  model VARCHAR NOT NULL,
  document_hash BIGINT NOT NULL,
  embedding BYTEA,
  embedded_at TIMESTAMP NOT NULL DEFAULT NOW(),
  checked_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_post_embeddings_checked_at ON post_embeddings (checked_at);

CREATE TABLE event_embeddings (
  event_id BIGINT PRIMARY KEY REFERENCES events (post_id) ON DELETE CASCADE,
  model VARCHAR NOT NULL,
  document_hash BIGINT NOT NULL,
  embedding BYTEA,
  embedded_at TIMESTAMP NOT NULL DEFAULT NOW(),
  checked_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_event_embeddings_checked_at ON event_embeddings (checked_at);

CREATE TABLE media_embeddings (
  media_id BIGINT PRIMARY KEY REFERENCES media ON DELETE CASCADE,
  model VARCHAR NOT NULL,
  document_hash BIGINT NOT NULL,
  embedding BYTEA,
  embedded_at TIMESTAMP NOT NULL DEFAULT NOW(),
  checked_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_media_embeddings_checked_at ON media_embeddings (checked_at);

CREATE TABLE user_profile_embeddings (
  user_id BIGINT PRIMARY KEY REFERENCES users ON DELETE CASCADE,
  model VARCHAR NOT NULL,
  document_hash BIGINT NOT NULL,
  embedding BYTEA,
  embedded_at TIMESTAMP NOT NULL DEFAULT NOW(),
  checked_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_user_profile_embeddings_checked_at ON user_profile_embeddings (checked_at);

-- 4. The server setting (ServerConfiguration.search_settings). NULL (every row that predates this
-- column) reads as "semantic search enabled" -- on by default.
ALTER TABLE server_configurations ADD COLUMN search_settings JSONB;
