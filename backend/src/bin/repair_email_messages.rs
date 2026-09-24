extern crate diesel;
extern crate rellm;

use diesel::*;
use rellm::models::{EmailHeaders, Message, MESSAGE_COLUMNS};
use rellm::schema::messages;
use rellm::web::email::{collect_addresses, display_address, sanitize_header_value};
use rellm::{db_connection, init_bin_logging, init_crypto, object_storage_connection};

/// TODO(2026-08-18): temporary, one-off migration. Once this has been run against every deployed
/// namespace's Messages (bullcitysocial, oakcitysocial, ato-band, jonline.io -- see
/// server_ci_cd.yml's `deploy_*` jobs), delete this file, its `COPY`/rename entries in
/// `deploys/docker/server/Dockerfile` and `.github/workflows/server_ci_cd.yml`, and this doc
/// comment's own TODO.
///
/// One-off backfill for `Message` rows written by `create_email_message` before it trimmed each
/// Stalwart header value's own trailing CRLF (see `build_raw_message`'s doc comment in
/// `web/email.rs`). That bug made `mail_parser` treat everything past the *first* header as body
/// text, so affected rows have `subject: None`, an all-empty `email_headers`, a
/// `<generated-*@rellm.internal>` fallback `email_message_id`, and a `body_text` that's really
/// the raw header block (each header followed by a spurious blank line) followed by the real
/// body.
///
/// This finds those rows via `Message::email_headers()` being the all-default `EmailHeaders`,
/// re-downloads the (also-corrupted, since it's the same buggy `raw_message` bytes) `.eml` each
/// one stored in object storage, undoes the specific corruption pattern the old bug produced, and re-parses
/// the repaired bytes the same way the fixed endpoint would have the first time.
///
/// Because the bug also defeated the endpoint's Message-ID-based dedup (every retry of the same
/// physical email got its own random fallback ID, so Stalwart's retries each landed as a separate
/// row), recovering the real Message-ID can reveal that two or more broken rows are actually the
/// same email. Rows are processed in `id` order so the earliest survives (gets updated in place)
/// and later duplicates are deleted -- `message_recipients`/`message_reads` cascade off
/// `messages.id` (see 2026-08-02-120000_create_messages / 2026-08-16-000000_create_message_reads),
/// so no separate cleanup is needed for those.
#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Repairing corrupted inbound-email Messages...");

    log::info!("Connecting to DB and object storage...");
    let mut conn = db_connection::establish_connection();
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    let mut candidates = messages::table
        .select(MESSAGE_COLUMNS)
        .filter(messages::email_object_storage_path.is_not_null())
        .order(messages::id.asc())
        .load::<Message>(&mut conn)
        .expect("Failed to load Messages");
    candidates.retain(|message| message.email_headers() == EmailHeaders::default());
    log::info!("Found {} corrupted Message(s) to repair.", candidates.len());

    let mut repaired_count = 0;
    let mut deduped_count = 0;
    let mut skipped_count = 0;

    for message in candidates {
        let object_storage_path = message.email_object_storage_path.clone().unwrap();
        let corrupted = match bucket.get_object(&object_storage_path).await {
            Ok(response) => response.as_slice().to_vec(),
            Err(e) => {
                log::error!(
                    "Message {}: failed to download {} from object storage: {:?}. Skipping.",
                    message.id,
                    object_storage_path,
                    e
                );
                skipped_count += 1;
                continue;
            }
        };

        let repaired_raw = repair_raw_message(&corrupted);
        let Some(parsed) = mail_parser::MessageParser::default().parse(&repaired_raw) else {
            log::warn!(
                "Message {}: repaired bytes still didn't parse as a valid message. Skipping.",
                message.id
            );
            skipped_count += 1;
            continue;
        };

        let Some(email_message_id) = parsed.message_id().map(|id| id.to_string()) else {
            log::warn!(
                "Message {}: repair found no Message-Id header (only {} originally recognized \
                 header(s)); leaving as-is for manual review.",
                message.id,
                header_prefix_len(&corrupted),
            );
            skipped_count += 1;
            continue;
        };

        let email_headers = EmailHeaders {
            from: parsed.from().and_then(display_address),
            to: collect_addresses(parsed.to()),
            cc: collect_addresses(parsed.cc()),
            bcc: vec![],
            date: parsed.header_raw("Date").map(sanitize_header_value),
            message_id: parsed.message_id().map(|id| id.to_string()),
            x_mailer: parsed.header_raw("X-Mailer").map(sanitize_header_value),
        };
        let subject = parsed.subject().map(|subject| subject.to_string());
        let body_text = parsed.body_text(0).map(|body| body.to_string());

        let update_result = diesel::update(messages::table.find(message.id))
            .set((
                messages::subject.eq(&subject),
                messages::body_text.eq(&body_text),
                messages::email_headers.eq(serde_json::to_value(&email_headers).unwrap()),
                messages::email_message_id.eq(&email_message_id),
            ))
            .execute(&mut conn);

        match update_result {
            Ok(_) => {
                log::info!(
                    "Message {}: repaired (subject={:?}, from={:?}, message_id={}).",
                    message.id,
                    subject,
                    email_headers.from,
                    email_message_id
                );
                repaired_count += 1;
            }
            // The real Message-ID collides with a row already updated earlier in this same run
            // (or one that was never corrupted) -- both are the same physical email, delivered
            // twice because the bug also defeated the endpoint's own dedup-by-Message-ID. Keep
            // the earlier row (already processed, since we go in `id` order) and drop this one.
            Err(diesel::result::Error::DatabaseError(
                diesel::result::DatabaseErrorKind::UniqueViolation,
                _,
            )) => {
                let survivor: Option<i64> = messages::table
                    .select(messages::id)
                    .filter(messages::email_message_id.eq(&email_message_id))
                    .first(&mut conn)
                    .optional()
                    .expect("Failed to look up surviving Message");
                log::info!(
                    "Message {}: duplicate of Message {:?} (Message-Id {}); deleting.",
                    message.id,
                    survivor,
                    email_message_id
                );
                diesel::delete(messages::table.find(message.id))
                    .execute(&mut conn)
                    .expect("Failed to delete duplicate Message");
                deduped_count += 1;
            }
            Err(e) => {
                log::error!(
                    "Message {}: failed to save repaired fields: {:?}. Skipping.",
                    message.id,
                    e
                );
                skipped_count += 1;
            }
        }
    }

    log::info!(
        "Done. Repaired {}, deduped/deleted {}, skipped {}.",
        repaired_count,
        deduped_count,
        skipped_count
    );
}

/// RFC5322 `field-name`: one or more octets that are printable US-ASCII excluding `:` (58) and
/// space (32..47 partially overlaps, but header names in practice never contain it either way).
fn looks_like_header_line(segment: &[u8]) -> bool {
    match segment.iter().position(|&b| b == b':') {
        Some(0) | None => false,
        Some(colon_index) => segment[..colon_index]
            .iter()
            .all(|&b| (33..=57).contains(&b) || (59..=126).contains(&b)),
    }
}

/// `build_raw_message` always writes a recovered header segment as literally `Name: Value` --
/// field names never contain `:` -- so splitting on the first `": "` reliably separates the two,
/// and re-running `sanitize_header_value` on `Value` undoes any embedded terminator that survived
/// `split_on_double_crlf` (see `repair_raw_message`'s doc comment). Falls back to sanitizing the
/// whole segment if `": "` isn't found, which shouldn't happen for anything `looks_like_header_line`
/// accepted, but is a harmless no-op rather than a panic if it somehow does.
fn resanitize_header_segment(segment: &[u8]) -> Vec<u8> {
    let text = String::from_utf8_lossy(segment);
    match text.find(": ") {
        Some(index) => {
            let (name, rest) = text.split_at(index);
            format!("{}: {}", name, sanitize_header_value(&rest[2..])).into_bytes()
        }
        None => sanitize_header_value(&text).into_bytes(),
    }
}

fn split_on_double_crlf(data: &[u8]) -> Vec<&[u8]> {
    let separator = b"\r\n\r\n";
    let mut segments = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i + separator.len() <= data.len() {
        if &data[i..i + separator.len()] == separator {
            segments.push(&data[start..i]);
            i += separator.len();
            start = i;
        } else {
            i += 1;
        }
    }
    segments.push(&data[start..]);
    segments
}

fn header_prefix_len(data: &[u8]) -> usize {
    split_on_double_crlf(data)
        .iter()
        .take_while(|segment| looks_like_header_line(segment))
        .count()
}

/// Reverses the corruption described in this bin's own doc comment above: the old
/// `build_raw_message` appended a `\r\n` after each header's value without trimming that value's
/// own trailing CRLF, so every header ended up followed by a spurious blank line, *and* the
/// (correct) blank line the loop added afterward -- to separate the header block from
/// `contents` -- became a second, redundant one on top of that. Splitting the corrupted bytes on
/// `\r\n\r\n` therefore yields one segment per original header, followed by a final segment that
/// is the real body with one leftover `\r\n` glued to its front (the fifth byte of the six-byte
/// `\r\n\r\n\r\n` run straddling the header block and the body, one short of a second full
/// separator match). Reassembling with a single `\r\n` between headers and stripping that leading
/// `\r\n` off the body recovers exactly what the fixed `build_raw_message` would have produced.
///
/// A message with no recognizable header segment up front (`header_count == 0`) is returned
/// unchanged -- this repair only applies to the specific corruption pattern above.
///
/// Each recovered header segment is also re-sanitized with `sanitize_header_value` (the same
/// function `build_raw_message` now applies up front) before being written back out: a header
/// whose original value had an embedded, non-doubled CRLF -- e.g. a server-generated `Received`
/// header, still folded across lines rather than truly unfolded despite Stalwart's docs -- carries
/// that embedded break straight through `split_on_double_crlf` untouched, since it isn't the
/// `\r\n\r\n` byte run that function looks for.
fn repair_raw_message(corrupted: &[u8]) -> Vec<u8> {
    let segments = split_on_double_crlf(corrupted);
    let header_count = segments
        .iter()
        .take_while(|segment| looks_like_header_line(segment))
        .count();
    if header_count == 0 {
        return corrupted.to_vec();
    }

    let mut repaired = Vec::new();
    for header in &segments[..header_count] {
        repaired.extend_from_slice(&resanitize_header_segment(header));
        repaired.extend_from_slice(b"\r\n");
    }
    repaired.extend_from_slice(b"\r\n");

    if let Some((first_body_segment, rest)) = segments[header_count..].split_first() {
        repaired.extend_from_slice(
            first_body_segment
                .strip_prefix(b"\r\n".as_slice())
                .unwrap_or(first_body_segment),
        );
        for segment in rest {
            repaired.extend_from_slice(b"\r\n\r\n");
            repaired.extend_from_slice(segment);
        }
    }
    repaired
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Byte-for-byte what the old, unfixed `build_raw_message` would have produced for a
    /// three-header message whose Stalwart values already carried their own trailing CRLF.
    fn corrupt(headers: &[(&str, &str)], contents: &str) -> Vec<u8> {
        let mut raw = Vec::new();
        for (name, value) in headers {
            raw.extend_from_slice(name.as_bytes());
            raw.extend_from_slice(b": ");
            raw.extend_from_slice(value.as_bytes());
            raw.extend_from_slice(b"\r\n"); // Stalwart's own terminator (the bug's premise).
            raw.extend_from_slice(b"\r\n"); // The old code's unconditional extra one.
        }
        raw.extend_from_slice(b"\r\n"); // The loop-final separator, now redundant.
        raw.extend_from_slice(contents.as_bytes());
        raw
    }

    #[test]
    fn repairs_corrupted_headers_and_preserves_body_paragraphs() {
        let corrupted = corrupt(
            &[
                ("To", "jon@ato.band"),
                ("From", "someone@example.com"),
                ("Subject", "Test"),
            ],
            "First paragraph.\r\n\r\nSecond paragraph.\r\n",
        );

        let repaired = repair_raw_message(&corrupted);
        let parsed = mail_parser::MessageParser::default()
            .parse(&repaired)
            .expect("repaired bytes should parse");

        assert_eq!(parsed.subject(), Some("Test"));
        assert_eq!(
            parsed.body_text(0).as_deref(),
            Some("First paragraph.\r\n\r\nSecond paragraph.\r\n")
        );
    }

    #[test]
    fn unfolds_a_header_value_with_an_embedded_line_break() {
        // Simulates a server-generated, still-folded `Received` header -- a single (not doubled)
        // CRLF inside the value, which `split_on_double_crlf` doesn't treat as a boundary, so it
        // survives into the header's segment and needs `resanitize_header_segment` to unfold it.
        let corrupted = corrupt(
            &[
                ("Received", "from foo\r\n\tby bar"),
                ("To", "jon@ato.band"),
                ("Subject", "Test"),
            ],
            "Body.\r\n",
        );

        let repaired = repair_raw_message(&corrupted);
        let parsed = mail_parser::MessageParser::default()
            .parse(&repaired)
            .expect("repaired bytes should parse");

        assert_eq!(
            parsed.header_raw("Received").map(str::trim),
            Some("from foo by bar")
        );
        assert_eq!(parsed.subject(), Some("Test"));
        assert_eq!(
            parsed.to().and_then(|to| to.first()).and_then(|a| a.address()),
            Some("jon@ato.band")
        );
    }

    #[test]
    fn leaves_an_already_correct_message_unchanged() {
        // Only a single header, so there's no "multiple headers sharing one un-doubled-CRLF
        // segment" ambiguity for `resanitize_header_segment` to (rightly, for actually corrupted
        // input) collapse -- see that function's doc comment. Real candidates for this repair
        // always have one segment per header already (that's the corruption being reversed), so
        // this only needs to demonstrate the single-header case is a true no-op.
        let clean = b"To: jon@ato.band\r\n\r\nBody.\r\n".to_vec();
        assert_eq!(repair_raw_message(&clean), clean);
    }
}
