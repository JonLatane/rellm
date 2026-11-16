-- One in-force subscription per Rellm Subdomain label (`SubdomainSettings.subdomain`, kept in the subscription's `details`).
-- Reserves the label atomically -- two buyers whose paid checkouts race can never both get it -- and serves
-- `logic::subdomains::find_active_subdomain_subscription`'s host lookup as an index probe instead of a scan.
CREATE UNIQUE INDEX idx_market_subscriptions_subdomain_label
    ON market_subscriptions ((details #>> '{settings,subdomain}'))
    WHERE product_type = 'PURCHASE_TYPE_SUBDOMAIN' AND service_terminated_at IS NULL;
