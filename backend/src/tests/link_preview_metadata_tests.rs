//! Specs for `parse_metadata_image_urls`, step 1 of link preview generation (the no-browser
//! metadata image lookup).

use crate::logic::parse_metadata_image_urls;

fn base() -> reqwest::Url {
    reqwest::Url::parse("https://example.com/events/halloween/").unwrap()
}

#[test]
fn prefers_og_image_over_twitter_image_regardless_of_order() {
    let html = r#"<head>
        <meta name="twitter:image" content="https://cdn.example.com/tw.jpg">
        <meta property="og:image" content="https://cdn.example.com/og.jpg" />
    </head>"#;
    assert_eq!(
        parse_metadata_image_urls(html, &base()),
        vec!["https://cdn.example.com/og.jpg", "https://cdn.example.com/tw.jpg"]
    );
}

#[test]
fn handles_attribute_order_quotes_case_and_entities() {
    let html = r#"
        <META CONTENT='https://cdn.example.com/a.jpg?x=1&amp;y=2' PROPERTY='og:image'>
        <meta content=https://cdn.example.com/b.jpg name=twitter:image>
    "#;
    assert_eq!(
        parse_metadata_image_urls(html, &base()),
        vec!["https://cdn.example.com/a.jpg?x=1&y=2", "https://cdn.example.com/b.jpg"]
    );
}

#[test]
fn resolves_relative_urls_dedupes_and_drops_non_http() {
    let html = r#"
        <meta property="og:image" content="/img/poster.png">
        <meta property="og:image:url" content="https://example.com/img/poster.png">
        <meta property="twitter:image" content="data:image/png;base64,AAAA">
        <meta property="og:image:secure_url" content="">
        <meta property="og:title" content="Not an image">
    "#;
    assert_eq!(
        parse_metadata_image_urls(html, &base()),
        vec!["https://example.com/img/poster.png"]
    );
}

#[test]
fn no_metadata_means_no_urls() {
    assert!(parse_metadata_image_urls("<html><body><img src='/x.png'></body></html>", &base()).is_empty());
}
