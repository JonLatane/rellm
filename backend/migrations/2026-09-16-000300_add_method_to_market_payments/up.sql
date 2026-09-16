-- Backs `MarketPayment.method`/`MarketRefund.method` (`protos/market.proto`) -- unlike every other
-- `stripe_*` column on the `market_*` tables (DB-only bookkeeping, never marshaled to a client),
-- this one's *contents* (card brand/last4/expiry) are exactly what gets marshaled into
-- `MarketPaymentMethod`/`MarketRefundMethod` for display -- Stripe's own PaymentMethod id itself is
-- never stored here, only the display-safe card summary resolved from it at charge time.
ALTER TABLE market_payments ADD COLUMN method JSONB;
