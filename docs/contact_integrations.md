# Sign-In & Contact Integrations

How Rellm asks users for consent before contacting them by SMS/email, and how the Twilio/Telnyx/Bird
SMS providers are wired up (both outbound sending and inbound delivery, including opt-out
handling). See the [`ContactMethod`](https://rellm.org/docs/protocol#rellm-ContactMethod) type in
the protocol docs for the wire format this is all built on, and
[`sms_verification_providers.md`](sms_verification_providers.md) (same directory) for a pricing/fee
comparison across SMS providers if you're choosing which one(s) to configure.

## Consent

Every [`ContactMethod`](https://rellm.org/docs/protocol#rellm-ContactMethod) (a user's `phone` or
`email`) carries its own `consent_state` (`CONTACT_CONSENT_GRANTED`/`CONTACT_CONSENT_REVOKED`) and
an append-only `consent_history` of every change, each server-timestamped. **No external service
may contact a user through a `ContactMethod` unless its `consent_state` is currently
`CONTACT_CONSENT_GRANTED`** -- this includes `StartContactMethodVerification`'s own outbound
verification SMS, which fails with `contact_consent_not_granted` until consent is granted, even
though the user is the one requesting the code (see
[`start_contact_method_verification.rs`](../backend/src/rpcs/users/start_contact_method_verification.rs)).
Consent is edited only via `UpdateUser` (self, or an Admin editing another user -- the same gate as
`value`/`visibility`), and every grant/revoke appends to `consent_history` rather than overwriting
it (see `apply_contact_method_update` in
[`update_user.rs`](../backend/src/rpcs/users/update_user.rs)).

On [`UserProfilePage.elm`](../frontends/elm-spa/src/Components/Pages/UserProfilePage.elm), the
expandable "Contact Methods" section shows a checkbox under each of Phone and Email: "Checking this
box indicates I consent to be contacted via SMS" (or "via email"). Checking/unchecking calls
`UpdateUser` immediately (no separate Save step) and, once at least one change exists, a "Show
History" toggle reveals the full `consent_history` (each entry's Granted/Revoked state and
timestamp).

`consent_state`/`consent_history` are only ever sent back to the `ContactMethod`'s own owner or an
`ADMIN` -- unlike `value` itself, this is never relaxed by `VIEW_PRIVATE_CONTACT_METHODS`, and every
other viewer sees it blanked to `CONTACT_CONSENT_REVOKED` with an empty history, regardless of the
`ContactMethod`'s own `visibility` (see `scrub_consent_for_viewer` in
[`user_marshaling.rs`](../backend/src/marshaling/user_marshaling.rs)).

## Server-side protocol toggles

`ServerConfiguration.supported_contact_protocols` is a server-wide admin setting -- independent of
per-user consent above -- declaring which contact protocols (`tel:`/`mailto:`) this server accepts
at all. It's edited via the master toggle at the top of the "Text messages (SMS)" and "Email" sections of
the Server Information page's "Sign In & Contact" tab
([`SignInAndContactTab.elm`](../frontends/elm-spa/src/Components/Pages/ServerInformationPage/SignInAndContactTab.elm)):
**"Enable SMS Sending"** and **"Enable Email Sending"**. Neither checkbox is ever disabled up
front -- checking one just calls `ConfigureServer`, and the server enforces the real invariant by
*erroring* (see `validate_configuration` in
[`configuration_validation.rs`](../backend/src/rpcs/validations/configuration_validation.rs)),
surfaced as a plain save error the same way every other admin form on this page shows one:

- **"Enable SMS Sending"** fails with `sms_contact_protocol_requires_a_configured_provider` unless
  at least one of Twilio/Telnyx/Bird is enabled in that same save.
- **"Enable Email Sending"** fails with `email_contact_protocol_requires_a_configured_provider`
  unless at least one of Postmark/SendGrid/Mailgun/Stalwart (sending) is enabled in that same save
  -- see [Email](#email) below.

## SMS

Three interchangeable SMS providers are supported -- Twilio, Telnyx, and Bird -- each configured
independently and optionally; an admin may enable any combination, and
`preferred_verification_apis` picks which is tried first when more than one is enabled (see
[`contact_verification.rs`](../backend/src/logic/contact_verification.rs)). All three are wired into
exactly one outbound call site (`send_verification_sms`), so consent enforcement (above) covers all
of them from a single choke point.

Each provider also has its own **inbound** delivery endpoint, registered as a webhook in that
provider's own dashboard, so Rellm can receive replies:

| Provider | Receive endpoint |
| --- | --- |
| Twilio | `POST https://<this site's domain>/contact_integrations/twilio/receive` |
| Telnyx | `POST https://<this site's domain>/contact_integrations/telnyx/receive` |
| Bird | `POST https://<this site's domain>/contact_integrations/bird/receive` |

All three are plain Rocket HTTP routes (see
[`contact_integrations_webhook.rs`](../backend/src/web/contact_integrations_webhook.rs)), not gRPC
endpoints, served from the same host/port as the rest of the site -- no separate port or subdomain
needed, same as `/webhooks/stripe`. Each parses that provider's own inbound-message payload shape
and, if the message body is exactly **"STOP"** (trimmed, case-insensitive -- not the full CTIA
opt-out keyword list of STOP/STOPALL/UNSUBSCRIBE/CANCEL/END/QUIT, just this one word this iteration),
revokes SMS consent for whichever user has that phone number on file (`consent_state` ->
`CONTACT_CONSENT_REVOKED`, appended to `consent_history` -- see
[`contact_consent.rs`](../backend/src/logic/contact_consent.rs)). Every other inbound message is
acknowledged (`200 OK`, so the provider doesn't keep retrying) and otherwise ignored -- Rellm has no
two-way SMS conversation feature to route a reply into.

**Signature verification is optional per provider, off by default.** Unlike `/webhooks/stripe`'s
always-on `Stripe-Signature` check, each provider's inbound signature is only verified once an
admin sets that provider's own "Webhook Signing Key" field *and* flips its "Use Webhook Signing
Key" toggle on, both on the Sign In & Contact tab (`TwilioConfig.twilio_webhook_signing_key`/
`use_twilio_webhook_signing_key`, and the equivalent pair on `TelnyxConfig`/`BirdConfig`) -- see the
per-provider steps below for exactly what value each key field expects. Leave the toggle off (the
default, even once a key is entered) and deliveries are accepted unverified; this is judged
acceptable even then because the only effect an unauthenticated (or spoofed) delivery can have
either way is *revoking* consent, never granting it -- the fail-safe direction. Whichever provider
you skip this for, or if it matters for your deployment regardless, restrict access to these three
paths at your reverse proxy/firewall to that provider's published IP ranges.

Since the key is a secret, the Sign In & Contact tab never shows its real value back (same
write-only treatment as every other credential here) -- entering a new value always replaces the
stored one, and leaving the field blank on a later save always keeps whatever's already stored
(there's no separate "clear" action -- disable the whole provider to remove it). The "Use Webhook
Signing Key" toggle is a separate, non-secret setting -- it's what the tab actually shows a
⚠️ warning next to (when off) as a reminder that deliveries aren't verified, since the key's own
presence is no longer visible to the client at all.

### Twilio

1. **Create/find your Account SID** -- Twilio Console home page, starts `AC`. This is
   `TwilioConfig.twilio_account_sid`; it's used only in the API's URL path, never as a credential.
2. **Create an API Key** -- Console → Account → API keys & tokens → Create API key. **Use an API
   Key, not the Account's Auth Token** -- Rellm authenticates every request with the API Key's
   SID (`SK...`, `twilio_api_key_sid`) and Secret (`twilio_api_key_secret`) as HTTP Basic Auth,
   deliberately never the more powerful Account Auth Token.
3. **Get a sending number** -- Console → Phone Numbers → buy or use an existing number capable of
   SMS. This is `twilio_from_number`.
4. **Register the inbound webhook** -- Console → Phone Numbers → Manage → Active numbers → your
   number → **Messaging** → "A message comes in" → **Webhook**, URL
   `https://<your domain>/contact_integrations/twilio/receive`, method `HTTP POST`.
5. **(Optional) Enable signature verification** -- Console → Account → API keys & tokens → copy
   the Account's **Auth Token** (not the API Key from step 2) into "Webhook Signing Key" on the
   Sign In & Contact tab, *and* turn on "Use Webhook Signing Key" (off by default even once a
   key is entered). This is the *only* place the Auth Token is ever entered -- it's never accepted
   for authenticating outbound API calls (step 2's API Key handles that). Rellm verifies the
   `X-Twilio-Signature` header against this token, computed over the exact URL registered in step 4
   plus the request's own POST parameters -- if the endpoint's URL ever changes, this still works as
   long as step 4's registration is updated to match.
6. Enter `twilio_enabled`, the Account SID, API Key SID/Secret, and From Number into the Twilio
   section of the Sign In & Contact tab.

### Telnyx

1. **Create a v2 API Key** -- Telnyx Portal → API Keys → Create API Key (starts `KEY`). This is
   `TelnyxConfig.telnyx_api_key`, sent as Bearer auth on Telnyx's Messaging API.
2. **Get a sending number and its Messaging Profile** -- Portal → Numbers, and Portal → Messaging →
   Messaging Profiles. `telnyx_from_number` must be assigned to `telnyx_messaging_profile_id` --
   both are required by Telnyx's `POST /v2/messages` to actually send.
3. **Register the inbound webhook** -- on that same Messaging Profile, **Inbound Settings** →
   Webhook URL, `https://<your domain>/contact_integrations/telnyx/receive`. Telnyx delivers
   `message.received` events here as JSON (`data.event_type`, `data.payload.from.phone_number`,
   `data.payload.text`).
4. **(Optional) Enable signature verification** -- Portal → Keys & Credentials → **Public Key**
   (account-level, same page as your API keys -- despite the name, this goes in "Webhook Signing
   Key" too, for consistency with the other providers), *and* turn on "Use Webhook Signing Key"
   (off by default even once a key is entered). Rellm verifies the
   `telnyx-signature-ed25519`/`telnyx-timestamp` headers (Ed25519) against it, and rejects a
   delivery whose `telnyx-timestamp` is more than 5 minutes old.
5. Enter `telnyx_enabled`, the API Key, From Number, and Messaging Profile ID into the Telnyx
   section of the Sign In & Contact tab.

### Bird

1. **Create a workspace access key** -- Bird dashboard → Developers/API → API access key. This is
   `BirdConfig.bird_access_key`, sent as Bearer auth on Bird's Messages API
   (`https://{region}.platform.bird.com/v1/sms/messages`).
2. **Get an originator and region** -- an owned number, alphanumeric sender ID, or short code
   configured in your Bird workspace (`bird_from`), and which regional API host your workspace
   uses, `"us1"` or `"eu1"` (`bird_region`, empty defaults to `"us1"`).
3. **Register the inbound webhook** -- Bird dashboard → Webhooks/subscriptions for your SMS
   channel, subscribing to the `sms.received` event, URL
   `https://<your domain>/contact_integrations/bird/receive`.
4. **(Optional) Enable signature verification** -- that same webhook subscription's own signing
   secret (starts with `whsec_`) goes in "Webhook Signing Key", *and* turn on "Use Webhook Signing
   Key" (off by default even once a key is entered). Bird uses the
   [Standard Webhooks](https://www.standardwebhooks.com) scheme (HMAC-SHA256 over
   `"{webhook-id}.{webhook-timestamp}.{raw body}"`); Rellm verifies the `webhook-id`/
   `webhook-timestamp`/`webhook-signature` headers against it, rejecting a delivery whose
   `webhook-timestamp` is more than 5 minutes old.
5. Enter `bird_enabled`, the access key, From, and Region into the Bird card of the SMS section of the
   Sign In & Contact tab.

## Email

**Sending** verification codes (and, later, login codes) to `mailto:` contact methods goes through
one of four independently-configured providers, any combination of which may be enabled. As with
SMS, "available" means *enabled and configured* (see each provider below); `ServerConfiguration.
preferred_email_apis` (admin-only) names which is tried first, then any other available provider is
tried in the fixed order Postmark, SendGrid, Mailgun, Stalwart (see `available_email_apis` in
[`email_sending.rs`](../backend/src/logic/contact_methods/email_sending.rs)), and
`available_email_apis` is public. Only the first available provider is used per send; there is no
automatic retry on the next one if it errors. The message is a short plain-text + HTML email naming
the server (`server_info.name` and its frontend host), the 6-digit code, a 10-minute expiry, and an
"if you didn't request this, ignore it" line. All credentials (Postmark server/account tokens,
SendGrid/Mailgun API keys, the Stalwart SMTP password and management token) are write-only, exactly
like the SMS providers' -- blank on save means "keep what's stored" -- and are redacted from the
server's own `ConfigureServer` logs.

**Whichever provider you choose, authenticate your sending domain** (all three below walk you to the
same place): publish the SPF and DKIM records the provider gives you, and add a DMARC record. A
sensible starting point is `_dmarc.<yourdomain>  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@<yourdomain>"`
-- monitor the aggregate reports for a couple of weeks, then tighten to `p=quarantine` and finally
`p=reject` once everything legitimate passes. Use a `From` address on a domain you've authenticated
(ideally a subdomain such as `mail.<yourdomain>` so transactional reputation stays separate from
your people's own mail); a `From` the provider hasn't verified is rejected (Postmark, SendGrid) or
lands in spam. Verification codes are one-time and short-lived, so a transactional stream with no
marketing content is the right fit.

### Postmark

1. Create a Postmark **Server** (https://account.postmarkapp.com) and, under *Sender Signatures*,
   verify either a single sender address or (preferred, for DKIM/SPF alignment) your whole
   **Domain** -- add the DKIM and Return-Path DNS records Postmark shows you.
2. Copy the Server's **Server API Token** (Server -> API Tokens). Optionally also copy your
   **Account API Token** (Account -> API Tokens); it is only used to *read* domain verification
   status on the Sign In & Contact tab.
3. Enter the tokens, the `From` address (must belong to the verified signature/domain), an optional
   display name, and (optionally) a Message Stream (blank = `outbound`, Postmark's default
   transactional stream) in the Postmark card, and turn "Enabled" on. Rellm sends via
   `POST https://api.postmarkapp.com/email` with `X-Postmark-Server-Token`.

### SendGrid

1. Create an API key (Settings -> API Keys) with at least **Mail Send** access (plus "Domain
   Authentication" read and "Stats" read if you want the tab to show authentication/delivery status).
2. Authenticate your domain (Settings -> Sender Authentication -> Domain Authentication) and publish
   the CNAME records SendGrid gives you; or, for testing only, verify a Single Sender.
3. Enter the key and `From` address in the SendGrid card. Set the region to `eu` only if your
   account/subuser is EU-regional (`api.eu.sendgrid.com`); leave it blank otherwise. Rellm sends via
   `POST /v3/mail/send` with `Authorization: Bearer <key>`.

### Mailgun

1. Add and verify a sending domain (Sending -> Domains), publishing the SPF/DKIM (and optional
   tracking) DNS records Mailgun shows. Pick the **EU** region when adding the domain if you need
   EU data residency.
2. Create a sending key (Domain settings -> Sending keys) or use your account's private API key.
3. Enter the key, the domain (e.g. `mg.example.com`), the region (`us`, or `eu` for
   `api.eu.mailgun.net`), and a `From` address on that domain in the Mailgun card. Rellm sends via
   `POST /v3/<domain>/messages` with HTTP Basic auth `api:<key>`.

### Stalwart (SMTP submission)

If you already run [Stalwart](https://stalw.art) in-cluster for receiving (see below and
[`deploys/email`](../deploys/email)), Rellm can send through it too, over SMTP *submission* (not
relay): this is the only provider that needs no third-party account, but then **you** own
deliverability (a clean IP, reverse DNS, SPF/DKIM/DMARC for the domain, and an outbound relay if your
host blocks port 25).

1. In Stalwart, create a principal (account or app password) Rellm will authenticate as and make
   sure it is allowed to send as your `From` address, and that Stalwart DKIM-signs that domain.
2. In the Stalwart card, enable "Send Emails through Stalwart" and set the SMTP host (usually the
   in-cluster Service, e.g. `stalwart.rellm-email.svc.cluster.local`), port, username/password and
   `From` address. Port `0`/`587` uses STARTTLS (the connection must upgrade, certificate-verified
   against the public web PKI roots -- so the host must present a publicly-trusted certificate whose
   name matches the host you entered); `465` uses implicit TLS. There is deliberately no unencrypted
   option.
3. (Optional) The management API URL/token on that card is read-only and only used by the tab's
   status display.

**Receiving** is a separate integration, unrelated to `ContactMethod`/consent/the SMS providers
above: [Stalwart](https://stalw.art) is a mail server that can run alongside Rellm in the same
Kubernetes cluster (see [`deploys/email`](../deploys/email)) and forward inbound mail to Rellm's
internal-only `POST :27705/email` endpoint (an [MTA Hook](https://stalw.art/docs/mta/filter/mtahooks/),
not a webhook you register anywhere external), which turns each message into a
Rellm `Message` addressed to whichever local users match its `RCPT TO` envelope recipients (see
[`email.rs`](../backend/src/web/email.rs)). This only works *in-cluster*: port 27705 is unsecured
and must never be exposed outside a `NetworkPolicy` restricting it to Stalwart's own pod -- there's
no equivalent of the SMS providers' public receive endpoints above.

`ServerConfiguration.stalwart_config.stalwart_receiving_enabled` gates this: the **"Receive Emails
from Stalwart"** toggle, on the Stalwart card of the "Email" section of the Sign In & Contact tab,
flips only `stalwart_config.stalwart_receiving_enabled` (creating the config if there is none yet); it
never clears `stalwart_config`, which also holds Stalwart's *sending* settings. The `:27705/email` route itself is always mounted (there's no reason to conditionally
start an otherwise-empty internal server around it) -- every call checks this flag first, and if
it's not enabled, returns a clean, permanent SMTP-level rejection (`action: "reject"`, `550`/`5.7.1`)
with a message a Stalwart admin can read directly in their own mail logs, rather than either
silently accepting mail or looking like a transient hook failure Stalwart would retry forever.

## SMS and email login

Rellm has three ways to sign in (and to create an account), all through `LoginRequest` /
`CreateAccountRequest`: **username + password** (always on), **SMS code** and **email code** (each
needs its `*_WITH_SMS` / `*_WITH_EMAIL` authentication feature *and* a configured provider -- see
below). The password path is the default and needs nothing from this page. The Elm account panel
shows only the paths the server offers; the Tamagui and Flutter apps currently use the password
path only. Only the SMS/email features are enforced server-side -- `LOGIN_WITH_PASSWORD` and
`CREATE_ACCOUNT_WITH_PASSWORD` are advisory and the password path can't be switched off.

Verified contact methods double as login credentials. Which flows a server offers is controlled by
`ServerConfiguration.authentication_features` (`LOGIN_WITH_SMS`, `LOGIN_WITH_EMAIL`,
`CREATE_ACCOUNT_WITH_SMS`, `CREATE_ACCOUNT_WITH_EMAIL`) *and* by the matching outbound provider
being set up (SMS: `verification_available`; email: `email_sending_available`). All of the code
handling -- generation, hashing, TTL, attempt cap, resend cooldown, constant-time comparison,
contact normalization, "which verified accounts own this contact" -- lives in one place,
[`contact_login.rs`](../backend/src/logic/contact_methods/contact_login.rs), shared by
`StartContactMethodVerification`/`VerifyContactMethod`, `Login`, and `CreateAccount`:

- Codes are 6 digits, expire after 10 minutes, allow 5 wrong guesses, and can be re-sent at most
  once a minute per contact. Phone numbers are normalized to `tel:+E164`; emails are lowercased
  and matched case-insensitively (the address is still *sent to* in the spelling the account stored).
- A contact method can be **verified on at most one account** (`contact_already_verified`; checked
  when starting a verification, on `VerifyContactMethod`, and on `CreateAccount`). Unverified copies
  on other accounts don't count and can't be used to log in. If (legacy data) two accounts do have
  the same verified contact, login needs `user_id` (`multiple_accounts_for_contact` otherwise).
- Sending is always gated by `ContactMethod.consent_state` (see [Consent](#consent)); the first
  phase of `CreateAccount` requires `CONTACT_CONSENT_GRANTED` and records it (with a server-timestamped
  history entry) on the new account's contact method.

### Login (`LoginRequest.sms` / `.email`)

Two requests. Phase 1 (no `code`) *always* returns the same `VerificationChallenge` response, with
`sent_to` echoing the requested value. A code is only actually sent if an account has that contact
verified, consent granted, and no code was sent within the last minute -- every other case (unknown
contact, unverified contact, revoked consent, cooldown, even a provider send failure) is logged
server-side only.

**Consent at sign-in.** The sign-in form shows a consent checkbox (`consent_to_contact` on
`SMSLoginRequest`/`EmailLoginRequest`, sent on both phases). It only matters when the account's stored
`consent_state` isn't `CONTACT_CONSENT_GRANTED` (the user unchecked it, or replied STOP): with it
checked, phase 1 sends the one-time code anyway; with it unchecked that account is sent nothing, as
above. Consent is **recorded only when the code is redeemed** (phase 2 valid *and* the box checked:
`consent_state` -> `GRANTED` plus a server-timestamped `consent_history` entry, no duplicate if already
granted) -- redeeming the code proves control of the contact, so an unauthenticated request can't flip
someone else's consent. A wrong/expired code, or phase 2 without the box, records nothing. A number
that replied STOP is still blocked by the SMS provider until it replies START, so that user may
not receive the code.

**Evidence of consent (`contact_consents`).** Consent on these forms is given before it can live on a
`ContactMethod.consent_history` (at sign-up no account exists yet, and may never; at sign-in it is only
copied onto the account once the code is redeemed). So every time a code is *reserved for sending* on the
strength of a checkbox (the row is written in the same transaction as the send ledger row, before the
provider is called, so a provider failure can't leave a message without it), an append-only `contact_consents` row is written: normalized contact value,
`flow` (`create_account`/`login`), `user_id` and `consented_at`. Sign-in rows carry the matched account;
a sign-up row has no `user_id` until the account is created (then the rows given since that attempt's pending verification began are tied to it, no second row; older orphaned rows of a deleted account are never claimed), and
stays without one if the signup is abandoned. Nothing is written when no message is sent. Unlike the
hourly send ledger, these rows are kept indefinitely (the `user_id` is nulled if the account is
deleted); they hold the phone/email, so treat them as PII. Phase 2 (with `code`) fails with `incorrect_code` in *every* failure case (no
such account, no code outstanding, wrong, expired, or attempt-exhausted) for the same reason; the
state is still updated server-side (guess counted; code cleared on expiry, burned on exhaustion). Known
limits of the anti-enumeration: the SMS/email send makes phase 1 slower for a real account than for
an unknown one, and `multiple_accounts_for_contact` does reveal that a contact is verified on more
than one account. Brute force is bounded by the attempt cap and the resend cooldown (5 guesses per
new code, one new code per minute, per account).

**One canonical contact value.** `normalize_contact_value` is the single function behind every
key -- cooldown, pending rows, the send ledger, advisory locks, the users lookup -- *and* the
delivery address: scheme optional and case-insensitive, emails lowercased, and anything extra
(`?query`, `#fragment`, `;param`, whitespace, a second recipient) is rejected rather than
stripped, with the same strict recipient check the email providers apply before sending. Phone
numbers are bare `tel:+E164`. So no spelling of a contact can mint a "different" key to dodge the
cooldown or per-contact cap.

**Sends are reserved atomically before the provider is called** (`send_reserved_code`, used by
signup phase 1, login phase 1 and `StartContactMethodVerification`). A short transaction takes the
contact's advisory lock (then, for signup, the global send lock -- always second), re-checks the
resend cooldown, the per-contact hourly cap and the global hourly cap under those locks, writes the
ledger row and the new code (pending row / `verification_in_progress` with its start time), and
commits. Only then is the provider called, outside any lock. Concurrent requests therefore see
the reservation and send nothing, instead of all passing the checks and each paying for a
message. If the provider call fails, the new code state is undone (the previous code/row is
restored, so a clean failure doesn't leave the caller behind a 60s cooldown for a message that
never arrived), but the **ledger row is kept**: a provider error can be a timeout on a message that
did go out, and the hourly caps (10 per contact, 200 global) are what bound an abuser looping on a
failing provider.

Check-and-save of codes on an account (`verification_in_progress`) happens in a transaction that
takes the contact's advisory lock and `SELECT ... FOR UPDATE`s the user row, then reloads the
contact -- so concurrent submissions can't both redeem a code, lose attempt counts, or restore a
cleared code. The send phase writes only `verification_in_progress` (reloaded under lock after the
slow provider call), so a contact edit made in the meantime isn't overwritten.

Server logs for these flows never contain usernames, contact values, passwords or codes -- only
user ids, the phase and the outcome.

The code is stored in plaintext in the account's own `ContactMethod.verification_in_progress` (the
same slot `StartContactMethodVerification` uses, so the two share one cooldown/attempt counter),
and the login is complete once it matches: `verification_in_progress` is cleared and tokens + the
`User` are returned exactly as for a password login.

### Account creation (`CreateAccountRequest` with `phone`/`email`)

If the matching `CREATE_ACCOUNT_WITH_*` feature is on, supplied contact methods must be proven before
the account exists (otherwise they're saved unverified, as always):

1. **Phase 1** (no `*_verification_code`): validates the username (not taken, checked *before*
   spending a message), consent granted, provider configured, contact not already verified elsewhere;
   then sends a code to each such contact and stores `sha256("<contact_value>:<code>")` in the
   `pending_contact_verifications` table (one row per contact value, upserted; no account yet).
   Resends within 60 seconds are refused (`verification_recently_sent`). As a global backstop against
   SMS/email cost abuse, once more than 200 codes have been sent in the last hour (any flow) further
   first phases fail with `too_many_verification_requests` (constant `MAX_PENDING_SENDS_PER_HOUR` in
   [`create_account.rs`](../backend/src/rpcs/authentication/create_account.rs)). The count comes from
   the append-only `contact_verification_sends` ledger (one row per actual send, written by
   `send_verification_code`), *not* from pending rows, which are overwritten on resend and deleted
   on expiry. The same ledger enforces a per-contact cap of 10 sends/hour
   (`MAX_SENDS_PER_CONTACT_PER_HOUR`): signup and `StartContactMethodVerification` report
   `too_many_verification_requests`; login phase 1 silently skips the send.
2. **Phase 2** (every pending contact's code supplied): TTL/attempt rules as above (expired or
   expired rows are deleted; *exhausted* rows are kept, with their original send time, so burning five
   guesses can't buy an immediate fresh code -- the same applies to an exhausted
   `verification_in_progress` on an account; a correct code isn't consumed by a failed request).
   Then, in one transaction that first takes a per-contact advisory lock and re-checks the code and
   that nobody else has verified the contact, the account is created with those contacts
   `verified_at = now` and the pending rows are deleted -- so two concurrent signups can't both
   claim one contact. Both phone and email given means both codes are required.

Contact methods on a signup are never trusted for server-owned fields, verified or not:
`verified_at`, `verification_in_progress`, `supported_by_server` and `consent_history` are all
rebuilt server-side (only `value`, `visibility` and `consent_state` come from the request).

An empty `password` makes the account **passwordless** (needs a contact whose `CREATE_ACCOUNT_WITH_*`
*and* `LOGIN_WITH_*` features are on, since SMS/email login is its only way in). Its `password_salted_hash` (NOT NULL) is a bcrypt hash of 32 random bytes nobody
knows, so the username/password path can never log into it. Expired `pending_contact_verifications`
rows are also removed by the `delete_expired_tokens` job.
