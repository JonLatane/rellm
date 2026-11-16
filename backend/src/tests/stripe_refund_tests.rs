//! Specs for `logic::market::stripe_payments::refund_payment_intent_at` -- the automatic refund a paid subdomain checkout
//! gets when its label can't be had -- against a local mock instead of the real Stripe API.

use crate::logic::stripe_payments::refund_payment_intent_at;
use crate::tests::factories::serve_capturing;

#[test]
fn refund_posts_the_payment_intent_with_an_idempotency_key_and_returns_the_refund_id() {
    let (base_url, captured) = serve_capturing(|_request, _prior| {
        ("HTTP/1.1 200 OK", serde_json::json!({ "id": "re_123", "status": "succeeded" }))
    });
    let id = refund_payment_intent_at(&base_url, "sk_test", "pi_abc", "subdomain_taken").unwrap();
    assert_eq!(id, "re_123");
    let requests = captured.lock().unwrap();
    let request = requests.first().expect("a request was made").to_lowercase();
    assert!(request.starts_with("post /v1/refunds"));
    assert!(request.contains("idempotency-key: rellm-refund-pi_abc"));
    assert!(request.contains("payment_intent=pi_abc"));
}

#[test]
fn a_rejected_refund_is_an_error_not_a_silent_success() {
    let (base_url, _captured) = serve_capturing(|_request, _prior| {
        ("HTTP/1.1 400 Bad Request", serde_json::json!({ "error": { "message": "already refunded" } }))
    });
    let error = refund_payment_intent_at(&base_url, "sk_test", "pi_abc", "x").unwrap_err();
    assert_eq!(error.message(), "stripe_refund_failed");
}
