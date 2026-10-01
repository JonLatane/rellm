use rocket::fairing::{Fairing, Info, Kind};
use rocket::http::Header;
use rocket::{Request, Response};

pub struct CORS;

#[rocket::async_trait]
impl Fairing for CORS {
    fn info(&self) -> Info {
        Info {
            name: "Add CORS headers to responses",
            kind: Kind::Response,
        }
    }

    async fn on_response<'r>(&self, _request: &'r Request<'_>, response: &mut Response<'r>) {
        // `media_file` asks for no CORS headers on anonymous requests when
        // `MediaSettings.block_cors_anonymous_media_access` is set (see `BLOCK_CORS_HEADER`). The
        // CSP is not CORS and stays, so `<img>`/`<video>` embeds keep working.
        if response.headers().contains(super::BLOCK_CORS_HEADER) {
            response.remove_header(super::BLOCK_CORS_HEADER);
            response.set_header(Header::new(
                "Content-Security-Policy",
                "object-src *; media-src *;",
            ));
            return;
        }
        response.set_header(Header::new("Access-Control-Allow-Origin", "*"));
        response.set_header(Header::new(
            "Access-Control-Allow-Methods",
            "POST, GET, PATCH, OPTIONS",
        ));
        response.set_header(Header::new("Access-Control-Allow-Headers", "*"));
        response.set_header(Header::new("Access-Control-Allow-Credentials", "true"));
        // We could let admins configure what external servers can use their instance as a media source here, using the rocket state.
        response.set_header(Header::new(
            "Content-Security-Policy",
            "object-src *; media-src *;",
        ));
    }
}
