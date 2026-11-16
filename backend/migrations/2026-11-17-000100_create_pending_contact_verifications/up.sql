-- Verification codes for contact methods that don't belong to any account *yet* -- i.e. the first
-- phase of CreateAccount with a phone/email (see `CreateAccountRequest` in authentication.proto).
-- (Login and `StartContactMethodVerification` keep their codes on the user's own `ContactMethod`
-- JSON instead -- `verification_in_progress` -- since there's an account to hang them on.)
--
-- One row per contact value (`tel:+1...` / `mailto:...`, normalized: emails lowercased). A fresh
-- send overwrites the row. Rows are short-lived: expired ones are deleted opportunistically and by
-- the `delete_expired_tokens` job.
CREATE TABLE pending_contact_verifications (
  id BIGSERIAL PRIMARY KEY,
  contact_value VARCHAR NOT NULL UNIQUE,
  -- The one-time code, stored as the hex SHA-256 of "<contact_value>:<code>" (never plaintext).
  code_hash VARCHAR NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  -- When the code was last (re)sent; drives the 60s resend cooldown and the 10 minute expiry.
  sent_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX pending_contact_verifications_sent_at_idx ON pending_contact_verifications (sent_at);
