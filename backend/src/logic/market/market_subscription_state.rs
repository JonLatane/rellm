//! Derives `MarketSubscription.state` (`protos/market.proto`'s `MarketSubscriptionState`) -- never
//! stored, always computed from the three timestamps that already fully describe a subscription's
//! lifecycle, so it can't drift out of sync with them.

use std::time::SystemTime;

use crate::protos::MarketSubscriptionState;

/// The instant a canceled subscription's paid-for service actually runs out: whichever is later of
/// `canceled_at`/`renews_at` (see `MarketSubscription.canceled_at`'s own proto doc). An unset
/// `renews_at` (a `PURCHASE_PERIOD_INDEFINITE` subscription, which never bills again) is never later
/// than anything, so it ends at `canceled_at` itself -- canceling one takes effect immediately.
pub fn service_ends_at(canceled_at: SystemTime, renews_at: Option<SystemTime>) -> SystemTime {
    renews_at.map_or(canceled_at, |renews_at| renews_at.max(canceled_at))
}

/// - not canceled -> `Active`
/// - canceled, paid-for period still running (and entitlement not yet revoked) -> `ActiveButCanceled`
/// - canceled and `service_terminated_at` is set, or the paid-for period is over (even if the
///   `renew_market_subscriptions` job hasn't gotten around to revoking the entitlement yet) ->
///   `Canceled`
///
/// `service_terminated_at` without `canceled_at` (never produced by this codebase) is treated as
/// `Canceled` too: the entitlement is gone, so presenting it as active would be a lie.
pub fn subscription_state(
    canceled_at: Option<SystemTime>,
    renews_at: Option<SystemTime>,
    service_terminated_at: Option<SystemTime>,
    now: SystemTime,
) -> MarketSubscriptionState {
    if service_terminated_at.is_some() {
        return MarketSubscriptionState::SubscriptionCanceled;
    }
    match canceled_at {
        None => MarketSubscriptionState::SubscriptionActive,
        Some(canceled_at) if service_ends_at(canceled_at, renews_at) > now => {
            MarketSubscriptionState::SubscriptionActiveButCanceled
        }
        Some(_) => MarketSubscriptionState::SubscriptionCanceled,
    }
}
