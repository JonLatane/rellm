-- The stylesheet text can be large, and `GetServerConfiguration` (which carries the rest of the custom CSS
-- configuration: media IDs and the forced theme) must never load it -- so it moves out of the
-- `custom_css_configuration` JSONB into its own TEXT column, which the `ServerConfiguration` model deliberately
-- leaves out of its column list (see `models::SERVER_CONFIGURATION_COLUMNS`). Only `GetCustomCSS`,
-- `ConfigureCustomCSS` and `/custom_css.css` read it.
ALTER TABLE server_configurations
ADD COLUMN custom_css TEXT;

-- Backfill from any existing JSON (either key spelling), then drop the key from the JSON.
UPDATE server_configurations
SET custom_css = COALESCE(custom_css_configuration ->> 'custom_css', custom_css_configuration ->> 'customCss'),
    custom_css_configuration = (custom_css_configuration - 'custom_css') - 'customCss'
WHERE custom_css_configuration IS NOT NULL
  AND (custom_css_configuration ? 'custom_css' OR custom_css_configuration ? 'customCss');
