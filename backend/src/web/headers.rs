use rocket::request::FromRequest;
use rocket::request::Outcome;
use rocket::Request;

pub struct AuthHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for AuthHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Authorization") {
            Some(h) => Outcome::Success(AuthHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

pub struct ContentTypeHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for ContentTypeHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Content-Type") {
            Some(h) => Outcome::Success(ContentTypeHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

pub struct FilenameHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for FilenameHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Filename") {
            Some(h) => Outcome::Success(FilenameHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

pub struct MediaTitleHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for MediaTitleHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Media-Title") {
            Some(h) => Outcome::Success(MediaTitleHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

pub struct MediaDescriptionHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for MediaDescriptionHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Media-Description") {
            Some(h) => Outcome::Success(MediaDescriptionHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

/// `Stripe-Signature` header on `POST /webhooks/stripe` deliveries -- see `web::stripe_webhook`.
pub struct StripeSignatureHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for StripeSignatureHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Stripe-Signature") {
            Some(h) => Outcome::Success(StripeSignatureHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

/// The `Host` header -- used by `web::contact_integrations_webhook`'s Twilio signature
/// verification to reconstruct the exact URL Twilio signed (see `TwilioConfig.
/// twilio_webhook_signing_key`'s own doc). Always used behind an `Option<_>` at the call site
/// (verification is only ever attempted when a signing key is actually configured), so a request
/// missing this header just fails that check rather than the whole request being rejected here.
pub struct HostHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for HostHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("Host") {
            Some(h) => Outcome::Success(HostHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

/// `X-Twilio-Signature` header on `POST /contact_integrations/twilio/receive` deliveries -- see
/// `web::contact_integrations_webhook`.
pub struct TwilioSignatureHeader<'a>(pub &'a str);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for TwilioSignatureHeader<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match req.headers().get_one("X-Twilio-Signature") {
            Some(h) => Outcome::Success(TwilioSignatureHeader(h)),
            None => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

/// `telnyx-signature-ed25519`/`telnyx-timestamp` headers on
/// `POST /contact_integrations/telnyx/receive` deliveries -- bundled into one guard since
/// `web::contact_integrations_webhook`'s verification always needs both together. Missing either
/// one fails the whole guard (see `HostHeader`'s own doc on why that's fine behind `Option<_>`).
pub struct TelnyxWebhookHeaders<'a> {
    pub signature: &'a str,
    pub timestamp: &'a str,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for TelnyxWebhookHeaders<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match (
            req.headers().get_one("telnyx-signature-ed25519"),
            req.headers().get_one("telnyx-timestamp"),
        ) {
            (Some(signature), Some(timestamp)) => {
                Outcome::Success(TelnyxWebhookHeaders { signature, timestamp })
            }
            _ => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}

/// `webhook-id`/`webhook-timestamp`/`webhook-signature` headers (the Standard Webhooks scheme --
/// see https://www.standardwebhooks.com) on `POST /contact_integrations/bird/receive` deliveries --
/// bundled into one guard since `web::contact_integrations_webhook`'s verification always needs
/// all three together. Missing any one fails the whole guard (see `HostHeader`'s own doc on why
/// that's fine behind `Option<_>`).
pub struct BirdWebhookHeaders<'a> {
    pub id: &'a str,
    pub timestamp: &'a str,
    pub signature: &'a str,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for BirdWebhookHeaders<'r> {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        match (
            req.headers().get_one("webhook-id"),
            req.headers().get_one("webhook-timestamp"),
            req.headers().get_one("webhook-signature"),
        ) {
            (Some(id), Some(timestamp), Some(signature)) => {
                Outcome::Success(BirdWebhookHeaders { id, timestamp, signature })
            }
            _ => Outcome::Error((rocket::http::Status::NotAcceptable, ())),
        }
    }
}
