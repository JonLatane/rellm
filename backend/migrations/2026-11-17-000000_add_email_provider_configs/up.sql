-- Email providers, parallel to twilio_config/bird_config/telnyx_config. All in ONE column
-- because Diesel's table! macro tops out at 32 columns without the (slow-to-compile)
-- `64-column-tables` feature, and server_configurations was already at 30. The JSON shape is
-- `{"postmark_config": PostmarkConfig, "sendgrid_config": SendgridConfig, "mailgun_config":
-- MailgunConfig, "preferred_email_apis": ["EMAIL_VERIFICATION_API_...", ...]}` -- see
-- `server_configuration_models::EmailProvidersJson`.
ALTER TABLE server_configurations ADD COLUMN email_providers_config JSONB;

-- `AuthenticationFeature` was split into per-method values (CREATE_ACCOUNT -> CREATE_ACCOUNT_WITH_PASSWORD,
-- LOGIN -> LOGIN_WITH_PASSWORD, plus new *_WITH_SMS / *_WITH_EMAIL). Stored as a JSON array of
-- enum names, so rename the old names in place.
UPDATE server_configurations
SET authentication_features = (
  SELECT COALESCE(jsonb_agg(
    CASE elem
      WHEN 'CREATE_ACCOUNT' THEN 'CREATE_ACCOUNT_WITH_PASSWORD'
      WHEN 'LOGIN' THEN 'LOGIN_WITH_PASSWORD'
      ELSE elem
    END
  ), '[]'::jsonb)
  FROM jsonb_array_elements_text(authentication_features) AS elem
)
WHERE jsonb_typeof(authentication_features) = 'array';
