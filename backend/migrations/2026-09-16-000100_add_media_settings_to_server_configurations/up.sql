-- Nullable, like `twilio_config`/`bird_config` -- `media_settings` is read-time-fallback deserialized
-- (see `ToProtoServerConfiguration::to_proto` in `marshaling/configuration_marshaling.rs`), not
-- SQL-backfilled, same convention as `deserialize_custom_tabs`.
ALTER TABLE server_configurations ADD COLUMN media_settings JSONB;
