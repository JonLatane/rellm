# Contact Integrations

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
at all. It's edited via two checkboxes at the top of the Server Information page's "Contact
Integrations" tab
([`ContactIntegrationsTab.elm`](../frontends/elm-spa/src/Components/Pages/ServerInformationPage/ContactIntegrationsTab.elm)):
**"Enable SMS Sending"** and **"Enable Email Sending"**. Neither checkbox is ever disabled up
front -- checking one just calls `ConfigureServer`, and the server enforces the real invariant by
*erroring* (see `validate_configuration` in
[`configuration_validation.rs`](../backend/src/rpcs/validations/configuration_validation.rs)),
surfaced as a plain save error the same way every other admin form on this page shows one:

- **"Enable SMS Sending"** fails with `sms_contact_protocol_requires_a_configured_provider` unless
  at least one of Twilio/Telnyx/Bird is enabled in that same save.
- **"Enable Email Sending"** always fails with `mailto_contact_protocol_not_supported` -- see
  [Email](#email) below.

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
Key" toggle on, both on the Contact Integrations tab (`TwilioConfig.twilio_webhook_signing_key`/
`use_twilio_webhook_signing_key`, and the equivalent pair on `TelnyxConfig`/`BirdConfig`) -- see the
per-provider steps below for exactly what value each key field expects. Leave the toggle off (the
default, even once a key is entered) and deliveries are accepted unverified; this is judged
acceptable even then because the only effect an unauthenticated (or spoofed) delivery can have
either way is *revoking* consent, never granting it -- the fail-safe direction. Whichever provider
you skip this for, or if it matters for your deployment regardless, restrict access to these three
paths at your reverse proxy/firewall to that provider's published IP ranges.

Since the key is a secret, the Contact Integrations tab never shows its real value back (same
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
   Contact Integrations tab, *and* turn on "Use Webhook Signing Key" (off by default even once a
   key is entered). This is the *only* place the Auth Token is ever entered -- it's never accepted
   for authenticating outbound API calls (step 2's API Key handles that). Rellm verifies the
   `X-Twilio-Signature` header against this token, computed over the exact URL registered in step 4
   plus the request's own POST parameters -- if the endpoint's URL ever changes, this still works as
   long as step 4's registration is updated to match.
6. Enter `twilio_enabled`, the Account SID, API Key SID/Secret, and From Number into the Twilio
   section of the Contact Integrations tab.

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
   section of the Contact Integrations tab.

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
5. Enter `bird_enabled`, the access key, From, and Region into the Bird section of the Contact
   Integrations tab.

## Email

**Sending:** no email contact integration exists yet -- `mailto:` contact methods have no
verification provider, and `ContactMethod.supported_by_server` is always `false` for them (see
`apply_contact_method_update` in
[`update_user.rs`](../backend/src/rpcs/users/update_user.rs)). Checking "Enable Email Sending" on
the Contact Integrations tab always fails with `mailto_contact_protocol_not_supported`.

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
from Stalwart"** checkbox, in the "Email Configuration" section of the Contact Integrations tab,
sets `stalwart_config` to `Some({stalwart_receiving_enabled: true})` when checked, or `None` (not
`Some({false})`) when unchecked. The `:27705/email` route itself is always mounted (there's no reason to conditionally
start an otherwise-empty internal server around it) -- every call checks this flag first, and if
it's not enabled, returns a clean, permanent SMTP-level rejection (`action: "reject"`, `550`/`5.7.1`)
with a message a Stalwart admin can read directly in their own mail logs, rather than either
silently accepting mail or looking like a transient hook failure Stalwart would retry forever.
