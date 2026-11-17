-- Append-only evidence of consent given on the sign-up / sign-in forms, at the moment a one-time
-- code was sent on the strength of it. Needed because that consent is given *before* it can live on
-- a `ContactMethod.consent_history`: at sign-up no account exists yet (and may never), and at
-- sign-in the form's checkbox is only copied onto the account once the code is redeemed -- so
-- without this table a message could be sent on consent we can't later show was given.
-- Kept indefinitely (not swept by `delete_expired_tokens`), unlike the abuse-cap ledger.
CREATE TABLE contact_consents (
  id BIGSERIAL PRIMARY KEY,
  -- Normalized (lowercased) `tel:`/`mailto:` value the consent covers.
  contact_value VARCHAR NOT NULL,
  -- Which form: 'create_account' or 'login'.
  flow VARCHAR NOT NULL,
  -- The account, once known: set at sign-in (the matched account) and, for sign-up, when the
  -- account is created. NULL for a sign-up that was never completed.
  user_id BIGINT REFERENCES users (id) ON DELETE SET NULL,
  consented_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX contact_consents_contact_value_idx ON contact_consents (contact_value, consented_at);
CREATE INDEX contact_consents_user_id_idx ON contact_consents (user_id);
