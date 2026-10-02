//! Calls the Gemini API's Interactions endpoint (`ai.google.dev/gemini-api/docs/image-generation`)
//! to generate (or edit, given reference images) an image. Used by
//! `rpcs::ai_providers::generate_media`.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde_json::json;
use tonic::{Code, Status};

use crate::logic::http_client::blocking_json_request;

/// One existing image passed to Gemini alongside the prompt, for image editing/reference-based
/// generation -- see `GenerateMediaRequest.media_ids`.
pub struct GeminiImageInput {
    pub content_type: String,
    pub bytes: Vec<u8>,
}

/// The image Gemini generated, ready to store as a new `Media` row.
pub struct GeneratedImage {
    pub content_type: String,
    pub bytes: Vec<u8>,
    /// This call's `usage.total_tokens`, if the response reported one -- what
    /// `rpcs::ai_providers::generate_media` actually deducts from a grantee's
    /// `AIProviderGrant.tokens_remaining`. `None` if the response had no `usage` object at
    /// all (defensive -- every request we've seen has one, but this shouldn't hard-fail generation
    /// itself if a future response ever omits it).
    pub tokens_used: Option<i64>,
}

const GEMINI_INTERACTIONS_URL: &str = "https://generativelanguage.googleapis.com/v1beta/interactions";

/// Calls Gemini's Interactions API (`POST /v1beta/interactions`) with `prompt` plus any
/// `reference_images` (existing Media supplied for editing/reference-based generation), requesting
/// a single square image back. A plain `reqwest` call via `http_client::blocking_json_request`
/// (same as `mastodon_sync`/`bluesky_sync`) rather than a client SDK -- Gemini doesn't publish a
/// Rust SDK for this endpoint.
///
/// The request/response shapes here (`input`/`type`/`mime_type`/`data`, `steps`/`content`) match
/// `ai.google.dev/gemini-api/docs/image-generation#gemini-image-editing`/`#rest`'s REST examples as
/// of when this was written -- `parse_generated_image` scans every step's `content` for the first
/// `{"type": "image", ...}` block, a little more robust to step ordering/type variance than
/// hardcoding `steps[0]`, in case the API's exact response shape drifts.
pub fn generate_image(
    api_key: &str,
    model_name: &str,
    prompt: &str,
    reference_images: &[GeminiImageInput],
) -> Result<GeneratedImage, Status> {
    let mut input = vec![json!({ "type": "text", "text": prompt })];
    for image in reference_images {
        input.push(json!({
            "type": "image",
            "mime_type": image.content_type,
            "data": STANDARD.encode(&image.bytes),
        }));
    }

    let body = json!({
        "model": model_name,
        "input": input,
        "response_format": {
            "type": "image",
            "aspect_ratio": "1:1",
        },
    });

    let api_key = api_key.to_string();
    let (status, value) = blocking_json_request(
        move |client| {
            client
                .post(GEMINI_INTERACTIONS_URL)
                .header("x-goog-api-key", api_key)
                .header("Content-Type", "application/json")
                .json(&body)
        },
        "gemini_request_failed",
    )?;

    if !status.is_success() {
        log::error!("Gemini image generation failed ({}): {:?}", status, value);
        return Err(Status::new(Code::FailedPrecondition, "gemini_request_failed"));
    }

    parse_generated_image(&value)
}

fn parse_generated_image(value: &serde_json::Value) -> Result<GeneratedImage, Status> {
    let image_block = value["steps"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|step| step["content"].as_array())
        .flatten()
        .find(|block| block["type"] == "image");

    let Some(image_block) = image_block else {
        log::error!("Gemini response had no image output: {:?}", value);
        return Err(Status::new(Code::Internal, "gemini_no_image_returned"));
    };

    let data = image_block["data"]
        .as_str()
        .ok_or_else(|| Status::new(Code::Internal, "gemini_no_image_returned"))?;
    let content_type = image_block["mime_type"]
        .as_str()
        .unwrap_or("image/png")
        .to_string();
    let bytes = STANDARD
        .decode(data)
        .map_err(|_| Status::new(Code::Internal, "gemini_invalid_image_data"))?;
    let tokens_used = value["usage"]["total_tokens"].as_i64();

    Ok(GeneratedImage { content_type, bytes, tokens_used })
}
