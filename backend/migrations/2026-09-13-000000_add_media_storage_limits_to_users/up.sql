-- Backs User.media_storage_limit_bytes (optional -- NULL means unlimited) and
-- User.media_storage_bytes_used (a denormalized sum of every owned Media's sizes[].size_bytes,
-- maintained by backend/src/logic/user_counts.rs's update_media_storage_used, same pattern as
-- follower_count/post_count/etc.).
ALTER TABLE users ADD COLUMN media_storage_limit_bytes BIGINT NULL DEFAULT NULL;
ALTER TABLE users ADD COLUMN media_storage_bytes_used BIGINT NOT NULL DEFAULT 0;
