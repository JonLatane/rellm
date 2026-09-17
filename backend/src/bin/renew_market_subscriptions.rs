extern crate diesel;
extern crate rellm;
use rellm::logic::{renew_subscriptions_of_type, terminate_subscriptions_of_type};
use rellm::marshaling::ALL_PURCHASE_TYPES;
use rellm::{db_connection, init_bin_logging, init_crypto};

/// Renews every due `market_subscriptions` row (`ANNUAL`/`MONTHLY` -- see
/// `PurchasePeriod.PURCHASE_PERIOD_INDEFINITE`'s own doc for why those never get a subscription
/// row at all) across all 4 `PurchaseType`s in one pass -- one binary rather than four, unlike most
/// other background jobs in this file, since the four types share one table
/// (`market_subscriptions.product_type` distinguishes them) and the exact same renewal logic
/// (`logic::market_renewal::renew_subscriptions_of_type`), just filtered differently. Also
/// terminates (revokes the entitlement of) every subscription whose cancellation has actually
/// taken effect via `terminate_subscriptions_of_type` -- see that function's own doc.
pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Renewing Market Subscriptions...");
    log::info!("Connecting to DB...");
    let pool = db_connection::establish_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    for purchase_type in ALL_PURCHASE_TYPES {
        log::info!("Renewing due {:?} subscriptions...", purchase_type);
        match renew_subscriptions_of_type(purchase_type, &mut conn) {
            Ok(()) => log::info!("Done renewing {:?} subscriptions.", purchase_type),
            Err(e) => log::error!(
                "Failed to renew {:?} subscriptions: {:?}. Proceeding to next PurchaseType.",
                purchase_type,
                e
            ),
        }
        log::info!("Terminating lapsed-canceled {:?} subscriptions...", purchase_type);
        match terminate_subscriptions_of_type(purchase_type, &mut conn) {
            Ok(()) => log::info!("Done terminating {:?} subscriptions.", purchase_type),
            Err(e) => log::error!(
                "Failed to terminate {:?} subscriptions: {:?}. Proceeding to next PurchaseType.",
                purchase_type,
                e
            ),
        }
    }
    log::info!("Done Renewing Market Subscriptions.");
}
