-- Backs MarketProduct.available_count/sold_count (market.proto): available_count is an admin-set
-- cap on how many subscriptions/purchases of this product can ever be active at once (0 = no cap,
-- the default -- every product created before this migration keeps behaving exactly as before);
-- sold_count is server-managed, incremented when a purchase/subscription is created (the Stripe
-- webhook, on checkout.session.completed) and decremented when a subscription is canceled
-- (CancelMarketSubscription), which is what "frees a slot" for someone else to buy.
ALTER TABLE market_products ADD COLUMN available_count INT NOT NULL DEFAULT 0;
ALTER TABLE market_products ADD COLUMN sold_count INT NOT NULL DEFAULT 0;
