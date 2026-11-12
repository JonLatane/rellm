//! RPCs backing `protos/market.proto`'s Rellm Marketplace -- see that file's own header comment
//! and `logic::market::market_fulfillment`/`logic::market::market_renewal`/`logic::stripe_payments`/
//! `web::stripe_webhook` for the fulfillment/renewal/Stripe side of the feature.

mod get_market_products;
pub use get_market_products::get_market_products;

mod create_market_product;
pub use create_market_product::create_market_product;

mod update_market_product;
pub use update_market_product::update_market_product;

mod get_market_subscriptions;
pub use get_market_subscriptions::get_market_subscriptions;

mod cancel_market_subscription;
pub use cancel_market_subscription::cancel_market_subscription;

mod update_market_subscription;
pub use update_market_subscription::{update_market_subscription, update_market_subscription_and_notify};

mod make_market_purchase;
pub use make_market_purchase::make_market_purchase;

// Opt-in push notifications for a Rellm hosting subscription's fulfillment chat: one file per RPC, sharing
// the access check in `market_subscription_push_access`.
mod market_subscription_push_access;

mod register_market_subscription_push;
pub use register_market_subscription_push::register_market_subscription_push;

mod unregister_market_subscription_push;
pub use unregister_market_subscription_push::unregister_market_subscription_push;

mod get_market_subscription_push_status;
pub use get_market_subscription_push_status::get_market_subscription_push_status;

mod mark_fulfillment_notes_read;
pub use mark_fulfillment_notes_read::mark_fulfillment_notes_read;
