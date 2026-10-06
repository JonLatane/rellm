-- Stored with the server configuration (so it is versioned like every other setting) but
-- deliberately never serialized into the `ServerConfiguration` proto -- see
-- `CustomCSSConfiguration`'s own doc. Read/written via `GetCustomCSS`/`ConfigureCustomCSS`.
ALTER TABLE server_configurations
ADD COLUMN custom_css_configuration JSONB;
