use lazy_static::lazy_static;
use regex::Regex;

use super::validate_regexp::validate_all_word_chars;
use super::validate_regexp::*;
use super::validate_strings::validate_length;
use tonic::{Code, Status};

lazy_static! {
    // A "standard" way to represent a federated Rellm user is federatedserver.com/username. But we also want
    // federatedserver.com/events and federatedserver.com/post/asdf123, etc. to be able to point to valid things.
    // Custom nav tab paths share this same top-level namespace, so they're checked against it too.
    static ref RESERVED_PATHS: Vec<&'static str> = vec![
        "app",
        "flutter",
        "tamagui",
        "elm",
        "elm_debug",
        "debug",
        "home",
        "web",
        "events",
        "event",
        "e",
        "posts",
        "post",
        "p",
        "groups",
        "group",
        "g",
        "people",
        "person",
        "author",
        "a",
        "member",
        "m",
        "server",
        "s",
        "servers",
        "about",
        "about_rellm",
        "u",
        "users",
        "user",
        "info",
        "info_shield",
        "robots.txt",
        "favicon.ico",
        "favicon.png",
        "sitemap.xml",
        "sitemap.xml.gz",
        "sitemap.xml.gz",
        "sitemap.xml.gz",
        "sitemap.xml.gz",
        "media",
        "backend_host",
        "frontend_host",
        "docs",
        "documentation",
        "event_ai",
        "third_party_auth",
        "third_party_auths",
        "auth",
        "auths",
        "oauth",
        "calendar.ics",
        "rss.xml",
        "atom.xml",
        "contact_integrations",
    ];
    // Custom tab paths share the RESERVED_PATHS namespace, but these specific values are
    // allowed since they're used as top-level containers (e.g. federatedserver.com/events)
    // rather than single-resource routes.
    static ref CUSTOM_TAB_RESERVED_PATHS: Vec<&'static str> = RESERVED_PATHS
        .iter()
        .filter(|path| !["events", "people", "users", "posts", "about", "market"].contains(path))
        .cloned()
        .collect();
    static ref CUSTOM_TAB_PATH_RE: Regex = Regex::new(r"^[a-z_]+$").unwrap();
    // Reserves every leading character a short Post/Event URL could start with (see
    // `rellm.proto`'s `### /[-._~:/?[]@!$&'()*+,;%=]{postId}: Short Post/Event URLs` routing
    // doc) so a username/custom tab path can never collide with one -- `UsernameOrCustomTab_.elm`
    // (Elm SPA) checks a path segment against this same set to decide whether to look it up as a
    // username/custom tab at all, or try it as a Post/Event id instead. (`#` is deliberately
    // excluded: URL fragments never reach the server, so it can't collide with a username/custom
    // tab path here in the first place, and isn't used for short URLs.)
    static ref RESERVED_LEAD_CHAR_RE: Regex = Regex::new(r"^[-._~:/?\[\]@!$&'()*+,;%=]").unwrap();
    // Twilio's own `To`/`From` params require E.164 (`+` followed by digits, no spaces/dashes/
    // parens) -- this matches a `tel:` `ContactMethod.value` against that shape (`tel:` prefix
    // plus the E.164 number itself), rejecting anything else before it ever reaches a Twilio call.
    static ref TEL_URL_RE: Regex = Regex::new(r"^tel:\+[0-9]+$").unwrap();
}

fn validate_no_reserved_lead_char(value: &str, entity_name: &str) -> Result<(), Status> {
    if RESERVED_LEAD_CHAR_RE.is_match(value) {
        return Err(Status::new(
            Code::InvalidArgument,
            format!("{}_starts_with_reserved_character", entity_name),
        ));
    }
    Ok(())
}

pub fn validate_username(value: &str) -> Result<(), Status> {
    validate_length(&value, "username", 1, 47)?;
    validate_all_word_chars(&value, "username")?;
    validate_no_reserved_lead_char(&value, "username")?;
    validate_reserved_values(&value, "username", &RESERVED_PATHS)
}

pub fn validate_custom_tab_path(path: &str, is_profile: bool) -> Result<(), Status> {
    // A profile tab's `path` *is* the username it links to (see the proto's own doc on
    // `is_profile`), so it's validated as a username instead (`validate_username`'s own
    // `[\w.-]+` word-char rule) -- not the stricter `[a-z_]+` below, which most real usernames
    // (mixed case, digits) would fail.
    if is_profile {
        return validate_username(path);
    }
    validate_reserved_values(path, "custom_tab_path", &CUSTOM_TAB_RESERVED_PATHS)?;
    if !CUSTOM_TAB_PATH_RE.is_match(path) {
        return Err(Status::new(
            Code::InvalidArgument,
            "custom_tab_path_must_match_[a-z_]",
        ));
    }
    // `CUSTOM_TAB_PATH_RE` (`^[a-z_]+$`) already excludes every reserved lead character except
    // `_` -- checked anyway, for the same reason `validate_username` is: staying obviously in
    // sync with the actual reserved set, not relying on that regex's specific alphabet forever.
    validate_no_reserved_lead_char(path, "custom_tab_path")
}

pub fn validate_password(value: &str) -> Result<(), Status> {
    validate_length(&value, "password", 8, 128)
}

pub fn validate_email(value: &Option<String>) -> Result<(), Status> {
    match value {
        Some(value) => validate_length(&value, "email", 1, 255),
        None => Ok(()),
    }
}
pub fn validate_phone(value: &Option<String>) -> Result<(), Status> {
    match value {
        Some(value) => {
            validate_length(&value, "phone", 1, 128)?;
            if !TEL_URL_RE.is_match(value) {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "phone_must_be_a_tel_url_in_e164_format",
                ));
            }
            Ok(())
        }
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RESERVED_LEAD_CHARS: &str = "-._~:/?[]@!$&'()*+,;%=";

    #[test]
    fn username_rejects_every_reserved_lead_character() {
        for c in RESERVED_LEAD_CHARS.chars() {
            let value = format!("{c}shortlink");
            assert!(
                validate_username(&value).is_err(),
                "expected username starting with {c:?} to be rejected, got Ok"
            );
        }
    }

    #[test]
    fn custom_tab_path_rejects_every_reserved_lead_character() {
        for c in RESERVED_LEAD_CHARS.chars() {
            let value = format!("{c}shortlink");
            assert!(
                validate_custom_tab_path(&value, false).is_err(),
                "expected custom_tab_path starting with {c:?} to be rejected, got Ok"
            );
        }
    }

    #[test]
    fn hash_is_not_a_reserved_lead_character() {
        // Deliberately excluded from the reserved-lead-character set -- URL fragments never
        // reach the server, so `#` can't collide with a username/custom_tab_path here (and isn't
        // used for short URLs at all). (`#...` is still rejected by `validate_username` overall,
        // same as any other non-word character -- just not by `validate_no_reserved_lead_char`.)
        assert!(!RESERVED_LEAD_CHAR_RE.is_match("#notreserved"));
    }

    #[test]
    fn reserved_lead_characters_are_still_fine_mid_string() {
        assert!(validate_username("a-b.c_d").is_ok());
    }

    #[test]
    fn ordinary_usernames_and_custom_tab_paths_are_unaffected() {
        assert!(validate_username("jon_latane99").is_ok());
        assert!(validate_custom_tab_path("weddings", false).is_ok());
    }
}
