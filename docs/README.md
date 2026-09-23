# Rellm Documentation

Pertinent Rellm documentation files:

* [`protocol.md`](./protocol.md) is Rellm's de-facto Markdown protocol document.
  * [`protocol.html`](./protocol.html) is simply a conversion of `protocol.md`.
* [`permissions_visibility_moderation.md`](./permissions_visibility_moderation.md) explains in plain English how Rellm's Permissions, Visibility, and Moderation features work.
* [`facebook_and_x_twitter_federation.md`](./facebook_and_x_twitter_federation.md) explains how Facebook (and Instagram) Sync works for both Posts and Occasions, why the latter posts to a Page's feed instead of creating a real Facebook Event, and the current (not-yet-functional) status of X (Twitter) sync.
* [`stripe_integration.md`](./stripe_integration.md) explains how to set up Stripe for Rellm's Market (API key permissions, webhook registration) and what the integration does/doesn't automatically sync onto the Checkout page.
* [`contact_integrations.md`](./contact_integrations.md) explains Rellm's per-`ContactMethod` consent model (SMS/email) and how to set up Twilio/Telnyx/Bird (API keys, inbound "STOP" webhook registration).
* [`sms_verification_providers.md`](./sms_verification_providers.md) is a pricing/fee comparison across SMS providers, for choosing which one(s) to configure.
