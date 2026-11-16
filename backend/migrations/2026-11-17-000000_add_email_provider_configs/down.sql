UPDATE server_configurations
SET authentication_features = (
  SELECT COALESCE(jsonb_agg(
    CASE elem
      WHEN 'CREATE_ACCOUNT_WITH_PASSWORD' THEN 'CREATE_ACCOUNT'
      WHEN 'LOGIN_WITH_PASSWORD' THEN 'LOGIN'
      ELSE elem
    END
  ), '[]'::jsonb)
  FROM jsonb_array_elements_text(authentication_features) AS elem
  WHERE elem NOT IN ('CREATE_ACCOUNT_WITH_SMS', 'CREATE_ACCOUNT_WITH_EMAIL', 'LOGIN_WITH_SMS', 'LOGIN_WITH_EMAIL')
)
WHERE jsonb_typeof(authentication_features) = 'array';

ALTER TABLE server_configurations DROP COLUMN email_providers_config;
