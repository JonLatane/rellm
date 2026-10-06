UPDATE server_configurations
SET custom_css_configuration = COALESCE(custom_css_configuration, '{}'::jsonb) || jsonb_build_object('custom_css', custom_css)
WHERE custom_css IS NOT NULL;

ALTER TABLE server_configurations DROP COLUMN custom_css;
