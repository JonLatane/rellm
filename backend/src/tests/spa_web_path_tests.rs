//! Link-preview metadata (`web::spa_web_path`) is user-controlled text interpolated into a page's `<head>`: it must
//! never be able to leave the `<meta content="…">` attribute (or `<title>`) it's written into.

use rocket::{get, http::Status, local::blocking::Client, routes};
use rocket_cache_response::CacheResponse;

use crate::web::{
    PreviewContext, RellmResponder, RellmSummary, SpaApp, meta_text, og_title, origin_for_host, spa_web_path,
};

fn context() -> PreviewContext {
    PreviewContext {
        origin: "https://example.test".to_string(),
        path: "/event/abc".to_string(),
        site_name: "Bull City | Social".to_string(),
    }
}

const HOSTILE_TITLE: &str = "\" /><script>window.__pwned=1</script><meta x=\"";
const HOSTILE_DESCRIPTION: &str = "desc \"/><img src=x onerror=window.__pwned2=1>";
const HOSTILE_IMAGE: &str = "/media/x\" onerror=\"window.__pwned3=1";

#[get("/hostile")]
async fn hostile() -> CacheResponse<Result<RellmResponder, Status>> {
    spa_web_path(
        SpaApp::Elm,
        "index.html",
        Some(RellmSummary {
            title: Some(HOSTILE_TITLE.to_string()),
            description: Some(HOSTILE_DESCRIPTION.to_string()),
            image: Some(HOSTILE_IMAGE.to_string()),
        }),
        false,
        &context(),
    )
    .await
}

#[get("/plain")]
async fn plain() -> CacheResponse<Result<RellmResponder, Status>> {
    spa_web_path(
        SpaApp::Elm,
        "index.html",
        Some(RellmSummary {
            title: Some("Fish & Chips | Post Details | Bull City | Social".to_string()),
            description: Some("First line\nsecond line".to_string()),
            image: Some("/media/abc".to_string()),
        }),
        false,
        &context(),
    )
    .await
}

#[get("/marker")]
async fn marker() -> CacheResponse<Result<RellmResponder, Status>> {
    spa_web_path(
        SpaApp::Elm,
        "index.html",
        Some(RellmSummary {
            title: Some("Rellm Social Link".to_string()),
            description: None,
            image: None,
        }),
        false,
        &context(),
    )
    .await
}

fn body_of(path: &str) -> String {
    let client = Client::tracked(rocket::build().mount("/", routes![hostile, plain, marker]))
        .expect("valid rocket instance");
    let response = client.get(path.to_string()).dispatch();
    assert_eq!(response.status(), Status::Ok, "{}", path);
    response.into_string().expect("a body")
}

#[test]
fn meta_text_escapes_everything_that_can_leave_an_attribute_or_start_markup() {
    assert_eq!(meta_text("a & b"), "a &amp; b");
    assert_eq!(
        meta_text("<b>\"x\"</b>"),
        "&lt;b&gt;&quot;x&quot;&lt;/b&gt;"
    );
    assert_eq!(meta_text("it's"), "it&#39;s");
    // A backslash is not an escape in HTML, so it is left alone (and `"` still becomes `&quot;`).
    assert_eq!(meta_text("a\\\"b"), "a\\&quot;b");
}

#[test]
fn meta_text_keeps_only_the_first_line() {
    assert_eq!(meta_text("one\ntwo"), "one");
    assert_eq!(meta_text(""), "");
}

#[test]
fn a_hostile_title_description_and_image_cannot_inject_markup() {
    let body = body_of("/hostile");
    // None of the injected tags/attributes exist as markup...
    assert!(!body.contains("<script>window.__pwned"), "{}", body);
    assert!(!body.contains("<img src=x"), "{}", body);
    assert!(!body.contains("\" onerror="), "{}", body);
    // ...they're all inert text inside the attributes, in the very tags the template already had.
    assert!(body.contains("&lt;script&gt;window.__pwned=1&lt;/script&gt;"));
    assert!(body.contains(
        "<meta property=\"og:image\" content=\"https://example.test/media/x&quot; onerror=&quot;window.__pwned3=1\"/>"
    ));
    assert!(body.contains("<title>&quot; /&gt;&lt;script&gt;"));
}

#[test]
fn an_ordinary_summary_renders_as_before() {
    let body = body_of("/plain");
    assert!(body.contains("<title>Fish &amp; Chips | Post Details | Bull City | Social</title>"));
    // No `|` in og:title (iMessage keeps only what follows the last one), and the site name is its own tag.
    assert!(
        body.contains("<meta property=\"og:title\" content=\"Fish &amp; Chips \u{2013} Post Details\" />")
    );
    assert!(body.contains("<meta property=\"og:site_name\" content=\"Bull City | Social\"/>"));
    assert!(body.contains("<meta property=\"og:url\" content=\"https://example.test/event/abc\"/>"));
    assert!(body.contains("<meta name=\"twitter:card\" content=\"summary_large_image\"/>"));
    assert!(body.contains("content=\"First line\""));
    // Both the OpenGraph and the plain description are the page's, not the generic Rellm text.
    assert!(!body.contains("easy-to-deploy"));
    // Crawlers need an absolute image URL.
    assert!(body.contains("<meta property=\"og:image\" content=\"https://example.test/media/abc\"/>"));
}

#[test]
fn a_title_containing_the_placeholder_text_still_fills_og_title() {
    let body = body_of("/marker");
    assert!(body.contains("<title>Rellm Social Link</title>"), "{}", body);
    assert!(body.contains("<meta property=\"og:title\" content=\"Rellm Social Link\" />"), "{}", body);
}

#[test]
fn og_title_drops_the_site_suffix_and_pipes() {
    assert_eq!(og_title("Movie | Event Details | Bull City | Social", "Bull City | Social"), "Movie \u{2013} Event Details");
    assert_eq!(og_title("People | Rellm", "Rellm"), "People");
    // A title that is only the site name stays.
    assert_eq!(og_title("Rellm", "Rellm"), "Rellm");
}

#[test]
fn origins_are_https_except_for_local_development() {
    assert_eq!(origin_for_host("bullcity.social", None), "https://bullcity.social");
    assert_eq!(origin_for_host("bullcity.social", Some(8000)), "https://bullcity.social");
    assert_eq!(origin_for_host("localhost", Some(8000)), "http://localhost:8000");
    assert_eq!(origin_for_host("127.0.0.1", None), "http://127.0.0.1");
}
