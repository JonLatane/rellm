# Stripe Integration

Rellm's Market ([`protos/market.proto`](../protos/market.proto)) bills through Stripe Checkout.
Every server "brings its own" Stripe account -- there's no Stripe Connect/platform setup, no shared
Rellm-operated account, and no Stripe SDK crate (every call is a plain `reqwest` REST request, same
pattern as [`logic::twilio_sync`](../backend/src/logic/twilio_sync.rs)). Implementation:
[`backend/src/logic/stripe_sync.rs`](../backend/src/logic/stripe_sync.rs) (the actual API calls),
[`backend/src/rpcs/market/make_market_purchase.rs`](../backend/src/rpcs/market/make_market_purchase.rs)
(starts a checkout), [`backend/src/web/stripe_webhook.rs`](../backend/src/web/stripe_webhook.rs)
(fulfills a completed purchase), and
[`backend/src/logic/market_renewal.rs`](../backend/src/logic/market_renewal.rs) (recurring charges).

## Setting up a site's Stripe account

Each site needs its own Stripe account (see "One account or many?" below if you're running several
sites). For each one:

### 1. Create the account

Sign up at [stripe.com](https://stripe.com), or add another account under your existing login via
**Create a new account**. If you're the one operator behind multiple sites, choose **Create an
account in an organization** rather than a fully separate account -- it groups every site's account
under one login/team without merging any of their money (separate balances, payouts, and tax
reporting either way), so you're not juggling a different login per site.

### 2. Get a Restricted API key

Don't use the full Secret key. Stripe's **Restricted keys** (Developers → API keys → Create
restricted key) let you scope exactly what the key can do, and Rellm's backend only ever touches
three resources:

| Resource | Access | Why |
| --- | --- | --- |
| Checkout Sessions | Write | `create_checkout_session_at` starts every purchase |
| PaymentIntents | Write | `create_off_session_payment_intent_at` (renewal charges), and reading the initial purchase's payment method off the webhook's PaymentIntent |
| PaymentMethods | Read | `get_payment_method_card_at` -- a saved card's brand/last4 for renewal receipts |

Everything else -- **Account**, Customers, Charges, Refunds, Products, Prices, Payouts, Balance,
Disputes, Invoices, etc. -- should stay **None**. Customers are created implicitly by Checkout
itself (passing an email is enough), and refunds are issued by hand in the Dashboard, not by this
app, so neither needs its own permission. (Account write access was deliberately never added here
either, even though it would let this app sync branding colors/business name onto the Checkout
page automatically -- see "What isn't synced" below.)

Copy the resulting key (`sk_...` for live mode, `rk_...` for a restricted key) -- this is
`StripeConfig.stripe_secret_key`.

### 3. Get the Publishable key

Developers → API keys → Publishable key (`pk_...`). Not secret, and not currently used
server-side at all (`StripeConfig.stripe_publishable_key`'s own proto doc) -- kept on file for a
possible future client-side Stripe Elements integration.

### 4. Register the webhook endpoint

This is the one step that's easy to get wrong, since it's the only part of the integration Stripe
calls *into* rather than this server calling *out*:

1. In the Stripe Dashboard: **Developers → Webhooks → Add endpoint**.
2. **Endpoint URL**: `https://<this site's own domain>/webhooks/stripe` -- e.g.
   `https://rellm.org/webhooks/stripe`. This is a plain Rocket HTTP route (see
   [`stripe_webhook.rs`](../backend/src/web/stripe_webhook.rs)), not a gRPC endpoint, and it's on
   the same host/port the rest of the site serves from -- no separate port or subdomain needed.
3. **Events to send**: at minimum, `checkout.session.completed` -- that's the only event type this
   endpoint actually acts on (everything else is acknowledged with `200 OK` and ignored, so
   Stripe doesn't keep retrying deliveries this server was never going to handle). Subscribing to
   "all events" is harmless if you'd rather not hand-pick, just unnecessary traffic.
4. After creating the endpoint, reveal its **Signing secret** (`whsec_...`) -- this is
   `StripeConfig.stripe_webhook_signing_secret`. It's *not* an API key and carries no permissions
   of its own; it's only ever used to verify the `Stripe-Signature` header on incoming deliveries
   (HMAC-SHA256 over `"{timestamp}.{raw_body}"`, 5-minute replay tolerance -- see
   `verify_signature` in `stripe_webhook.rs`), so a request without a valid signature never reaches
   any purchase-fulfilling code at all.

If you ever change domains (or add a preview/staging site), remember the webhook endpoint URL is
tied to that specific domain -- add a new endpoint (and new signing secret) rather than expecting
the old one to still work.

### 5. Enter everything into Rellm

As an Admin, the Market tab on the Server Information page
([`Components.Pages.ServerInformationPage.MarketTab`](../frontends/elm-spa/src/Components/Pages/ServerInformationPage/MarketTab.elm))
has the Stripe config form: `stripe_enabled`, the secret key, the publishable key, and the webhook
signing secret. The two secret fields are write-only (same treatment as
`TwilioConfig.twilio_api_key_secret`) -- they're never sent back to the client once saved, and
leaving either blank on a later edit preserves whatever's already stored rather than clearing it
(see `configure_server.rs`'s own merge-on-blank handling).

`MarketSettings.stripe_configured` (computed live on every `GetServerConfiguration`, public even to
non-admins) reflects whether `stripe_enabled` is true *and* a secret key is actually on file --
that's what greys out the "Buy" button with "Stripe is not configured" on `/market`/
`/market/product/:id` until this is done.

## What the integration actually does

- **Checkout Session creation** (`create_checkout_session_at`) -- `mode=payment`,
  `payment_intent_data[setup_future_usage]=off_session` (so the PaymentMethod can be reused for
  off-session renewal charges later), one `price_data` line item (no pre-created Stripe Price
  object needed).
- **Product naming** (`market_summary::stripe_product_name`) -- the Checkout page's line item name
  is a human-readable description built from the product's own details and this server's
  `ServerInfo.short_name` (falling back to `name`, then `"Rellm"`), e.g. `"5GB Media Storage on
  Rellm.org"`, `"Rellm Hosting, 1GB DB + 5GB Object Storage, from Rellm.org"` -- not the raw
  `PURCHASE_TYPE_MEDIA_STORAGE`-style enum name.
- **Statement descriptor** (`sanitize_statement_descriptor`) -- the same short/display name, sent
  as `payment_intent_data[statement_descriptor]` so it (rather than some generic default) is what
  shows up on the buyer's own bank/card statement, truncated to Stripe's 22-character limit with
  disallowed characters (`< > \ ' "`) stripped.
- **Error surfacing** -- a failed Checkout Session creation (e.g. a product priced below Stripe's
  $0.50 minimum) returns Stripe's own `error.message` in the RPC's Status, not just an opaque
  `stripe_checkout_session_failed` key, so the actual reason shows up in the "Buy" button's error
  text without a server log dive.
- **Fulfillment** (`web::stripe_webhook`) -- happens *only* from the `checkout.session.completed`
  webhook, never from `MakeMarketPurchase` itself, so an abandoned checkout never leaves a
  half-created `MarketPurchase`/`MarketSubscription` behind. Idempotent: a redelivered event is a
  no-op if a `MarketPurchase` already exists for that Checkout Session id.
- **Renewals** (`logic::market_renewal`) -- recurring (`ANNUAL`/`MONTHLY`) subscriptions are billed
  by this server itself calling `create_off_session_payment_intent_at` against the saved
  Customer/PaymentMethod, not through another Checkout Session or Stripe's own Billing/Subscriptions
  product.

### What isn't synced

Stripe's hosted Checkout page's *branding* (accent color, business name shown in its header) comes
from that Stripe account's own Dashboard settings (Settings → Branding / Business profile), not
from anything this app sends per-request -- Stripe has no per-Checkout-Session equivalent, only an
account-wide one (`POST /v1/account`). This was deliberately left unautomated: doing it would need
an **Account: Write** permission on the API key, which is broader access than this integration
otherwise needs, and it's a one-time Dashboard setting anyway -- set your logo/color/business name
once per Stripe account and it applies to every Checkout Session, invoice, and receipt email that
account ever sends.

Similarly, whether Stripe emails the buyer a receipt at all is a Dashboard-only toggle (Settings →
Customer emails → "Successful payments") -- not something settable via the API, so it needs to be
turned on by hand per Stripe account if you want it.

## One account or many?

Two supported setups:

- **Separate Stripe account per site** (the default assumption) -- each site's admin sets up its
  own account and enters its own keys via that site's own Market tab, as above. No extra tooling
  needed.
- **One shared Stripe account across sites** -- e.g. every community you personally operate bills
  through the same account. Copy `stripe_config` from one site's `server_configurations` row to
  another's with [`deploys/copy_server_configuration.sh`](../deploys/copy_server_configuration.sh)
  (also wired up as `make copy_server_configuration SOURCE=... TARGET=... COLUMN=stripe_config` in
  [`deploys/Makefile`](../deploys/Makefile)): it clones the target's active `server_configurations`
  row with the new column's value, retires the old row, and activates the new one in a transaction
  -- the same pattern `ConfigureServer` itself uses, so it's auditable/rollback-able the same way a
  normal admin edit is.

  Each site still needs its *own* webhook endpoint registered on that shared account (step 4 above)
  pointing at its own domain -- Stripe webhook endpoints are tied to a URL, not to "the account,"
  so sharing a `stripe_secret_key` doesn't mean sharing a webhook signing secret too.
