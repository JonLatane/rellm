-- Opt-in links between one of a user's Web Push subscriptions (`push_subscriptions`, one per
-- user+browser endpoint -- the same ones new-Message notifications use) and a Rellm hosting
-- `market_subscriptions` row, so a new `FulfillmentNote` on that subscription's fulfillment chat
-- pushes a notification to exactly the devices that asked for it (`RegisterMarketSubscriptionPush`).
--
-- Both sides cascade: pruning a dead endpoint (`web_push::send_push`'s 404/410 handling, or
-- `UnregisterPushSubscription`) silently drops its links too, and deleting a subscription row
-- (there's no API for that today, but tests and admins do it by hand) can't leave orphans.
CREATE TABLE market_subscription_push_subscriptions(
  id BIGSERIAL PRIMARY KEY,
  market_subscription_id BIGINT NOT NULL REFERENCES market_subscriptions(id) ON DELETE CASCADE,
  push_subscription_id BIGINT NOT NULL REFERENCES push_subscriptions(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Registering the same device twice is a no-op, not a second notification.
  UNIQUE (market_subscription_id, push_subscription_id)
);
-- The UNIQUE index above covers lookups by market_subscription_id; this one covers the
-- "which links does this push subscription have" direction (status checks, cascade deletes).
CREATE INDEX idx_market_subscription_push_subscriptions_push_subscription_id
  ON market_subscription_push_subscriptions(push_subscription_id);
