-- Renames `messages.email_minio_path` to `messages.email_object_storage_path`, matching the
-- backend-wide rename of MinIO-branded identifiers to the generic `object_storage` (MinIO's OSS
-- project was archived and we're moving to a drop-in fork, but don't want our own naming tied to
-- either vendor going forward). See `models::message_models::Message`/`NewMessage`.
ALTER TABLE messages RENAME COLUMN email_minio_path TO email_object_storage_path;
