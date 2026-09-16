-- Backs `protos/market.proto`'s Rellm Marketplace: `market_products` is the storefront (admin
-- managed `Product`s), `market_subscriptions`/`market_purchases`/`market_payments` record what
-- buyers actually bought/paid, mirroring `ai_model_providers`/`ai_model_provider_grants`' two-table
-- (+JSONB) pattern -- plain columns for everything queryable, one JSONB `details` column per
-- polymorphic `oneof details` (`{"<snake_case_variant>": {...fields...}}`, same convention as
-- `ai_providers.configuration`). Stripe identifiers are DB-only bookkeeping, never marshaled into
-- proto types -- same as `users.password_salted_hash`.
--
-- `market_payments` backs both `Payment` and `Refund` in one table (positive `amount` = Payment,
-- negative = Refund) -- see `market.proto`'s own header comment.
CREATE TABLE market_products (
  id BIGSERIAL PRIMARY KEY,
  product_type VARCHAR NOT NULL,
  period VARCHAR NOT NULL,
  amount INT4 NOT NULL,
  currency INT4 NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  delisted_at TIMESTAMP
);

CREATE TABLE market_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  buyer_id BIGINT NOT NULL REFERENCES users(id),
  product_id BIGINT NOT NULL REFERENCES market_products(id),
  product_type VARCHAR NOT NULL,
  period VARCHAR NOT NULL,
  amount INT4 NOT NULL,
  currency INT4 NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  renews_at TIMESTAMP,
  ended_at TIMESTAMP,
  -- Stripe bookkeeping only -- never marshaled to a client. Reused across renewals for
  -- off-session `PaymentIntent`s (see `logic::stripe_sync::create_off_session_payment_intent_at`).
  stripe_customer_id VARCHAR,
  stripe_payment_method_id VARCHAR
);
CREATE INDEX idx_market_subscriptions_buyer_id ON market_subscriptions(buyer_id);
CREATE INDEX idx_market_subscriptions_product_id ON market_subscriptions(product_id);
-- Used by the renewal background jobs to find subscriptions due to bill.
CREATE INDEX idx_market_subscriptions_renews_at ON market_subscriptions(renews_at) WHERE ended_at IS NULL;

CREATE TABLE market_purchases (
  id BIGSERIAL PRIMARY KEY,
  buyer_id BIGINT NOT NULL REFERENCES users(id),
  product_id BIGINT NOT NULL REFERENCES market_products(id),
  -- NULL for a PURCHASE_PERIOD_INDEFINITE product's one-off purchase -- see
  -- `PurchasePeriod.PURCHASE_PERIOD_INDEFINITE`'s own doc.
  subscription_id BIGINT REFERENCES market_subscriptions(id),
  product_type VARCHAR NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  -- Stripe bookkeeping only -- never marshaled to a client.
  stripe_checkout_session_id VARCHAR,
  stripe_payment_intent_id VARCHAR
);
CREATE INDEX idx_market_purchases_buyer_id ON market_purchases(buyer_id);
CREATE INDEX idx_market_purchases_product_id ON market_purchases(product_id);
CREATE INDEX idx_market_purchases_subscription_id ON market_purchases(subscription_id);

-- One table for both `Payment` and `Refund` (see this file's own header comment).
CREATE TABLE market_payments (
  id BIGSERIAL PRIMARY KEY,
  purchase_id BIGINT NOT NULL REFERENCES market_purchases(id),
  amount INT4 NOT NULL,
  currency INT4 NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  -- Stripe bookkeeping only -- never marshaled to a client.
  stripe_payment_intent_id VARCHAR,
  stripe_refund_id VARCHAR
);
CREATE INDEX idx_market_payments_purchase_id ON market_payments(purchase_id);
