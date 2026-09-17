-- Backs ServerConfiguration.market_settings (server_configuration.proto) -- the public "is this
-- server's Market open" signal used for federated multi-server Market browsing. Nullable, same
-- convention as media_settings/twilio_config/etc.: a missing/legacy row falls back to
-- MarketSettings { enabled: false } at read time (see configuration_marshaling.rs), not a SQL
-- backfill.
ALTER TABLE server_configurations ADD COLUMN market_settings JSONB;
