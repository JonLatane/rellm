-- Rellm Subdomains move from the subscription (`market_subscriptions.details.settings`) onto the user, so a subdomain
-- works the same whether it was bought (a `PURCHASE_TYPE_SUBDOMAIN` subscription) or enabled by an admin without one
-- (`subdomain_granted_by_admin`). A user's subdomain is *enabled* while they hold an in-force subscription or the grant.
ALTER TABLE users
    -- The DNS label the user holds (their lower-cased username, fixed when first enabled); NULL when none. Set only
    -- while the subdomain is enabled -- released when the grant and the subscription are both gone.
    ADD COLUMN subdomain VARCHAR,
    ADD COLUMN subdomain_granted_by_admin BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN subdomain_share_followers BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN subdomain_share_following BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN subdomain_share_friends BOOLEAN NOT NULL DEFAULT FALSE,
    -- A serialized `CustomCSSConfiguration` (its `custom_css` text can be up to 64 KiB, so it is never part of `USER_COLUMNS`).
    ADD COLUMN subdomain_custom_css JSONB;

-- Reserves the label atomically -- two users whose paid checkouts or admin grants race can never both get it -- and
-- serves `logic::subdomains::resolve_subdomain`'s host lookup as an index probe.
CREATE UNIQUE INDEX idx_users_subdomain ON users (subdomain) WHERE subdomain IS NOT NULL;

-- Carry every buyer's settings over from their subdomain subscription (the in-force one if they have several).
WITH latest AS (
    SELECT DISTINCT ON (buyer_id)
        buyer_id,
        details -> 'settings' AS settings,
        (service_terminated_at IS NULL) AS in_force
    FROM market_subscriptions
    WHERE product_type = 'PURCHASE_TYPE_SUBDOMAIN'
    ORDER BY buyer_id, (service_terminated_at IS NULL) DESC, created_at DESC, id DESC
)
UPDATE users u SET
    subdomain = CASE WHEN latest.in_force AND latest.settings ->> 'subdomain' <> '' THEN latest.settings ->> 'subdomain' END,
    subdomain_share_followers = COALESCE((latest.settings ->> 'share_content_from_followers')::boolean, FALSE),
    subdomain_share_following = COALESCE((latest.settings ->> 'share_content_from_following')::boolean, FALSE),
    subdomain_share_friends = COALESCE((latest.settings ->> 'share_content_from_friends')::boolean, FALSE),
    subdomain_custom_css = latest.settings -> 'custom_css_configuration'
FROM latest
WHERE u.id = latest.buyer_id AND latest.settings IS NOT NULL;

-- The subscription keeps only its fulfillment bookkeeping.
DROP INDEX idx_market_subscriptions_subdomain_label;
UPDATE market_subscriptions SET details = details - 'settings' WHERE product_type = 'PURCHASE_TYPE_SUBDOMAIN';
