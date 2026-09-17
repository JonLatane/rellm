//! RPCs backing `protos/market.proto`'s Rellm Marketplace -- see that file's own header comment
//! and `logic::market_fulfillment`/`logic::market_renewal`/`logic::stripe_sync`/
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
pub use update_market_subscription::update_market_subscription;

mod make_market_purchase;
pub use make_market_purchase::make_market_purchase;
