-- `ContactMethod.use_for_sign_in` (JSON on users.phone / users.email) and `users.has_password`.
--
-- Until now every verified contact method could be used for SMS/email sign-in, and an account
-- created that way has no password (`password_salted_hash` is a hash of random bytes). Keep that
-- working: every already-verified contact method becomes a sign-in method.
UPDATE users
SET phone = jsonb_set(phone, '{use_for_sign_in}', 'true'::jsonb)
WHERE phone IS NOT NULL
  AND jsonb_typeof(phone->'verified_at') IS NOT NULL
  AND jsonb_typeof(phone->'verified_at') <> 'null';
UPDATE users
SET email = jsonb_set(email, '{use_for_sign_in}', 'true'::jsonb)
WHERE email IS NOT NULL
  AND jsonb_typeof(email->'verified_at') IS NOT NULL
  AND jsonb_typeof(email->'verified_at') <> 'null';

-- Whether the account has a password it can sign in with. Existing accounts are assumed to have one
-- (a passwordless account created before this column can't be told apart from one with a password;
-- they can set one with ResetPassword). New passwordless accounts set this to false.
ALTER TABLE users ADD COLUMN has_password BOOLEAN NOT NULL DEFAULT true;
