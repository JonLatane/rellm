use rocket::{
    http::{ContentType, Status},
    request::{FromRequest, Outcome},
    response::{self, Responder},
    routes, Request, Response, Route, State,
};
use std::io::Cursor;

use crate::logic::{
    custom_css_etag, custom_css_stylesheet, get_custom_css_configuration, if_none_match_matches,
};
use crate::rpcs::get_server_configuration_proto;
use crate::web::RocketState;

lazy_static! {
    pub static ref CUSTOM_CSS_PAGES: Vec<Route> = routes![custom_css, elm_custom_css];
}

/// The raw `If-None-Match` request header, if any.
struct IfNoneMatch(Option<String>);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for IfNoneMatch {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        Outcome::Success(IfNoneMatch(
            req.headers().get_one("If-None-Match").map(str::to_string),
        ))
    }
}

/// `200` with the stylesheet, or a bodiless `304` when the client's cached copy is still current.
/// `Cache-Control: no-cache` means browsers revalidate (a cheap `304`) on every load rather than
/// trusting a possibly-stale copy, so a `ConfigureCustomCSS` save shows up on the very next page
/// load -- the `ETag` is a hash of the stylesheet's content, so unrelated config saves don't
/// invalidate it.
pub struct CustomCssResponder {
    status: Status,
    etag: String,
    body: String,
}

impl<'r> Responder<'r, 'static> for CustomCssResponder {
    fn respond_to(self, _request: &'r Request<'_>) -> response::Result<'static> {
        let mut response = Response::build();
        response
            .status(self.status)
            .header(ContentType::CSS)
            .raw_header("ETag", self.etag)
            .raw_header("Cache-Control", "no-cache");
        if self.status == Status::Ok {
            response.sized_body(self.body.len(), Cursor::new(self.body));
        }
        response.ok()
    }
}

fn serve_custom_css(
    state: &State<RocketState>,
    if_none_match: IfNoneMatch,
) -> Result<CustomCssResponder, Status> {
    let mut conn = state.pool.get().map_err(|_| Status::InternalServerError)?;
    let config =
        get_custom_css_configuration(&mut conn).map_err(|_| Status::InternalServerError)?;
    // The server's configured primary/nav colors become the `--primary-color`/`--nav-color` variables.
    let colors = get_server_configuration_proto(&mut conn)
        .ok()
        .and_then(|c| c.server_info)
        .and_then(|info| info.colors);
    let body = custom_css_stylesheet(&config, colors.as_ref());
    let etag = custom_css_etag(&body);
    let status = if if_none_match
        .0
        .as_deref()
        .is_some_and(|header| if_none_match_matches(header, &etag))
    {
        Status::NotModified
    } else {
        Status::Ok
    };
    Ok(CustomCssResponder { status, etag, body })
}

/// The Elm SPA's custom stylesheet when it's served at the site root (`rellmBasePath == ""` in
/// `index.html`). Deliberately not gated on `ElmSpaAtRoot`: it's one small public file no other
/// frontend uses, and a literal route outranks every `/<file..>` catch-all.
#[rocket::get("/custom_css.css")]
async fn custom_css(
    state: &State<RocketState>,
    if_none_match: IfNoneMatch,
) -> Result<CustomCssResponder, Status> {
    serve_custom_css(state, if_none_match)
}

/// Same stylesheet at `/elm/custom_css.css`, for when the Elm SPA is served under `/elm` -- without
/// this, `elm_file`'s `/elm/<file..>` fallback would answer with `index.html`.
#[rocket::get("/elm/custom_css.css")]
async fn elm_custom_css(
    state: &State<RocketState>,
    if_none_match: IfNoneMatch,
) -> Result<CustomCssResponder, Status> {
    serve_custom_css(state, if_none_match)
}
