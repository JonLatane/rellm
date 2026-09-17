-- Renames market_subscriptions.ended_at to canceled_at (set once the buyer/admin explicitly
-- cancels via CancelMarketSubscription, or a renewal charge fails) and adds service_terminated_at
-- (set once renew_market_subscriptions.rs actually revokes the entitlement, which only happens
-- after both canceled_at and renews_at have passed -- see market.proto's own doc on
-- MarketSubscription.canceled_at/service_terminated_at).
ALTER TABLE market_subscriptions RENAME COLUMN ended_at TO canceled_at;
ALTER TABLE market_subscriptions ADD COLUMN service_terminated_at TIMESTAMP;

DROP INDEX idx_market_subscriptions_renews_at;
CREATE INDEX idx_market_subscriptions_renews_at ON market_subscriptions(renews_at) WHERE canceled_at IS NULL;
CREATE INDEX idx_market_subscriptions_terminable ON market_subscriptions(renews_at)
  WHERE canceled_at IS NOT NULL AND service_terminated_at IS NULL;
