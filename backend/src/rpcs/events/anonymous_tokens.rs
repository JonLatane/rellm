//! Parsing for the `anonymous_attendee_auth_token` request fields (`GetEventsRequest`,
//! `GetRsvpsRequest`) and the `/calendar.ics` endpoint's `anonymous_auth_token` parameter, all of
//! which accept the same two shapes -- the same ones the web frontends keep in their
//! `?anonymousAuthToken=` URL parameter, so they can pass it straight through:
//!
//! * a plain `<token>` -- one anonymous RSVP's private token; or
//! * `<occasionId>-<token>--<occasionId>-<token>--...` -- several at once (one per Occasion the
//!   viewer has anonymously RSVP'd to).
//!
//! Tokens are unguessable secrets that identify one RSVP, so the occasion-id prefix is only
//! advisory: every token found is simply tried against every RSVP being considered. (Tokens are
//! hex and occasion ids base58, so neither can contain the `-` separators.)

pub fn parse_anonymous_auth_tokens(raw: Option<&str>) -> Vec<String> {
    let mut tokens: Vec<String> = raw
        .unwrap_or("")
        .split("--")
        .filter_map(|part| {
            let part = part.trim();
            let token = match part.split_once('-') {
                Some((_occasion_id, token)) => token,
                None => part,
            };
            if token.is_empty() {
                None
            } else {
                Some(token.to_string())
            }
        })
        .collect();
    tokens.sort();
    tokens.dedup();
    tokens
}

#[cfg(test)]
mod tests {
    use super::parse_anonymous_auth_tokens;

    #[test]
    fn parses_plain_and_multi_occasion_tokens() {
        assert!(parse_anonymous_auth_tokens(None).is_empty());
        assert!(parse_anonymous_auth_tokens(Some("")).is_empty());
        assert_eq!(parse_anonymous_auth_tokens(Some("abc123")), vec!["abc123"]);
        assert_eq!(
            parse_anonymous_auth_tokens(Some("7LmN6T-aaa--9XyZ12-bbb--7LmN6T-aaa")),
            vec!["aaa", "bbb"]
        );
        assert!(parse_anonymous_auth_tokens(Some("7LmN6T-")).is_empty());
    }
}
