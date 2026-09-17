DROP INDEX idx_market_subscriptions_terminable;
DROP INDEX idx_market_subscriptions_renews_at;

ALTER TABLE market_subscriptions DROP COLUMN service_terminated_at;
ALTER TABLE market_subscriptions RENAME COLUMN canceled_at TO ended_at;

CREATE INDEX idx_market_subscriptions_renews_at ON market_subscriptions(renews_at) WHERE ended_at IS NULL;
