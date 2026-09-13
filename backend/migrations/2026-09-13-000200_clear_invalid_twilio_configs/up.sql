-- Data-only migration. `TwilioConfig` switched from Account SID + Auth Token authentication to a
-- Twilio API Key (SID + Secret) -- see that message's own doc in server_configuration.proto for
-- why the account's own (unscoped, unrevocable-without-rotating-everything) Auth Token is
-- deliberately no longer supported. Any `twilio_config` already stored under the old shape has its
-- credential in the wrong field (what's now `twilio_api_key_secret` held either the old Auth Token
-- or, worse, an API Key SID mistaken for it) and is not a valid credential pair under the new
-- scheme regardless -- clearing it forces a clean re-entry through the (now also fixed) admin UI
-- rather than silently misbehaving with half-migrated data.
UPDATE server_configurations SET twilio_config = NULL WHERE twilio_config IS NOT NULL;
