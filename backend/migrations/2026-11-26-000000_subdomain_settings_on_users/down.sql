-- A canceled subscription whose paid period has run out is over; the renewal job would terminate it, and the label
-- index below only counts subscriptions that aren't terminated.
UPDATE market_subscriptions SET service_terminated_at = NOW()
WHERE product_type = 'PURCHASE_TYPE_SUBDOMAIN' AND service_terminated_at IS NULL AND canceled_at IS NOT NULL
  AND GREATEST(canceled_at, COALESCE(renews_at, canceled_at)) <= NOW();

-- Put each user's settings back on their newest subdomain subscription (in-force first), as before. `subdomain_of` is
-- left out (it needs the base58 proto id encoding; the server always fills it in from the owner when serving). A user
-- who holds no label gets their lower-cased username only if no other user holds it.
UPDATE market_subscriptions s SET details = jsonb_set(
    s.details, '{settings}',
    jsonb_strip_nulls(jsonb_build_object(
        'subdomain', COALESCE(u.subdomain, CASE WHEN NOT EXISTS (
            SELECT 1 FROM users o WHERE o.id <> u.id AND o.subdomain = lower(u.username)
        ) THEN lower(u.username) END),
        'share_content_from_followers', u.subdomain_share_followers,
        'share_content_from_following', u.subdomain_share_following,
        'share_content_from_friends', u.subdomain_share_friends,
        'custom_css_configuration', u.subdomain_custom_css
    )), true)
FROM users u
WHERE s.buyer_id = u.id AND s.product_type = 'PURCHASE_TYPE_SUBDOMAIN'
  AND s.id = (SELECT s2.id FROM market_subscriptions s2 WHERE s2.buyer_id = u.id AND s2.product_type = 'PURCHASE_TYPE_SUBDOMAIN'
              ORDER BY (s2.service_terminated_at IS NULL) DESC, s2.created_at DESC, s2.id DESC LIMIT 1);

CREATE UNIQUE INDEX idx_market_subscriptions_subdomain_label
    ON market_subscriptions ((details #>> '{settings,subdomain}'))
    WHERE product_type = 'PURCHASE_TYPE_SUBDOMAIN' AND service_terminated_at IS NULL;

DROP INDEX idx_users_subdomain;
ALTER TABLE users
    DROP COLUMN subdomain,
    DROP COLUMN subdomain_granted_by_admin,
    DROP COLUMN subdomain_share_followers,
    DROP COLUMN subdomain_share_following,
    DROP COLUMN subdomain_share_friends,
    DROP COLUMN subdomain_custom_css;
