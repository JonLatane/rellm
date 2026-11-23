-- One row per verification code actually *sent* (SMS/email), whatever flow sent it. Unlike
-- `pending_contact_verifications` (one row per contact, overwritten on resend, deleted on
-- exhaustion/expiry) this is an append-only ledger, so the abuse caps -- a global hourly cap on
-- signup sends and a per-contact hourly cap -- count every send. Rows older than an hour are
-- irrelevant and removed by the `delete_expired_tokens` job.
CREATE TABLE contact_verification_sends (
  id BIGSERIAL PRIMARY KEY,
  -- Normalized (lowercased) `tel:`/`mailto:` value the code was sent to.
  contact_value VARCHAR NOT NULL,
  sent_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX contact_verification_sends_sent_at_idx ON contact_verification_sends (sent_at);
CREATE INDEX contact_verification_sends_contact_value_idx ON contact_verification_sends (contact_value, sent_at);
