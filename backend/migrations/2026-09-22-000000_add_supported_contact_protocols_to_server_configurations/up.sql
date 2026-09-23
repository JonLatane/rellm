-- Your SQL goes here
ALTER TABLE server_configurations
ADD COLUMN supported_contact_protocols JSONB;
