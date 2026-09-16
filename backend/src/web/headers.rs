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
