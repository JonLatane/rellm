-- Nullable, like `twilio_config`/`bird_config` -- `StripeConfig.stripe_secret_key`/
-- `stripe_webhook_signing_secret` are write-only (blanked in `ToProtoServerConfiguration::to_proto`),
-- same convention as `twilio_config`'s `twilio_api_key_secret`.
ALTER TABLE server_configurations ADD COLUMN stripe_config JSONB;
