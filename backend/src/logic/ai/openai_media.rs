//! Calls an OpenAI-Images-API-shaped endpoint to generate a new image (`POST
//! {base_url}/v1/images/generations`, no reference images) or edit existing ones (`POST
//! {base_url}/v1/images/edits`, one or more reference images -- accepted as a multipart file array).
//! Used by `rpcs::ai_providers::generate_media` for both OpenAI itself
//! (`platform.openai.com/docs/guides/image-generation`) and DigitalOcean's Serverless Inference API
//! (`docs.digitalocean.com/products/inference`), which re-hosts GPT Image (and Stable Diffusion)
//! models behind the exact same request/response shape, just a different `base_url`/key --
//! DigitalOcean has no edits-equivalent endpoint, but that's enforced by `ai_model_catalog.rs` never
//! giving its models `AiModelCapability::ImageEditing` (so `generate_media.rs` never calls `edit`
//! for one), not by anything here. Mirrors `gemini_media`'s own shape (a `content_type`/`bytes`
//! result struct); `OpenAi`-prefixed names avoid colliding with `gemini_media`'s own
//! `generate_image`/`GeneratedImage`, both re-exported flat into `crate::logic`.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde_json::json;
use tonic::{Code, Status};

use crate::logic::http_client::blocking_json_request;

/// One existing image passed to the edits endpoint alongside the prompt.
#[derive(Clone)]
pub struct OpenAiImageInput {
    pub content_type: String,
    pub bytes: Vec<u8>,
}

/// The image the API generated, ready to store as a new `Media` row.
pub struct OpenAiGeneratedImage {
    pub content_type: String,
    pub bytes: Vec<u8>,
    /// This call's `usage.total_tokens`, if the response reported one -- what
    /// `rpcs::ai_providers::generate_media` actually deducts from a grantee's
    /// `AIProviderGrant.tokens_remaining`. `None` for models that don't bill by token at all
    /// (e.g. DigitalOcean's `stable-diffusion-3.5-large`, priced per-image) -- `generate_media.rs`
    /// falls back to a flat charge in that case.
    pub tokens_used: Option<i64>,
}

/// Generates (no `reference_images`) or edits (one or more `reference_images`) an image via
/// `model_name`, against `base_url` -- see the module doc for which endpoint each case hits, and
/// which `base_url`s this is actually called with.
pub fn openai_generate_image(
    base_url: &str,
    api_key: &str,
    model_name: &str,
    prompt: &str,
    reference_images: &[OpenAiImageInput],
) -> Result<OpenAiGeneratedImage, Status> {
    if reference_images.is_empty() {
        generate(base_url, api_key, model_name, prompt)
    } else {
        edit(base_url, api_key, model_name, prompt, reference_images)
    }
}

fn generate(base_url: &str, api_key: &str, model_name: &str, prompt: &str) -> Result<OpenAiGeneratedImage, Status> {
    let url = format!("{base_url}/v1/images/generations");
    let api_key = api_key.to_string();
    let body = json!({
        "model": model_name,
        "prompt": prompt,
        "size": "1024x1024",
    });

    let (status, value) = blocking_json_request(
        move |client| client.post(&url).bearer_auth(&api_key).json(&body),
        "openai_request_failed",
    )?;

    if !status.is_success() {
        log::error!("OpenAI-shaped image generation failed ({}): {:?}", status, value);
        return Err(Status::new(Code::FailedPrecondition, "openai_request_failed"));
    }
    parse_generated_image(&value)
}

fn edit(
    base_url: &str,
    api_key: &str,
    model_name: &str,
    prompt: &str,
    reference_images: &[OpenAiImageInput],
) -> Result<OpenAiGeneratedImage, Status> {
    let url = format!("{base_url}/v1/images/edits");
    let api_key = api_key.to_string();
    let model_name = model_name.to_string();
    let prompt = prompt.to_string();
    let reference_images = reference_images.to_vec();

    let (status, value) = blocking_json_request(
        move |client| {
            let mut form = reqwest::blocking::multipart::Form::new()
                .text("model", model_name.clone())
                .text("prompt", prompt.clone());
            for (index, image) in reference_images.iter().enumerate() {
                let part = reqwest::blocking::multipart::Part::bytes(image.bytes.clone())
                    .file_name(format!("reference-{index}"))
                    .mime_str(&image.content_type)
                    .unwrap_or_else(|_| reqwest::blocking::multipart::Part::bytes(image.bytes.clone()));
                // The edits endpoint takes its reference images as a repeated `image[]` field.
                form = form.part("image[]", part);
            }
            client.post(&url).bearer_auth(&api_key).multipart(form)
        },
        "openai_request_failed",
    )?;

    if !status.is_success() {
        log::error!("OpenAI-shaped image edit failed ({}): {:?}", status, value);
        return Err(Status::new(Code::FailedPrecondition, "openai_request_failed"));
    }
    parse_generated_image(&value)
}

/// Both endpoints return the same shape: `{"data": [{"b64_json": "..."}]}`. This API family always
/// returns PNG unless a different `output_format` is explicitly requested (not done here), so
/// `content_type` is hardcoded rather than read back from the response.
fn parse_generated_image(value: &serde_json::Value) -> Result<OpenAiGeneratedImage, Status> {
    let data = value["data"][0]["b64_json"]
        .as_str()
        .ok_or_else(|| {
            log::error!("OpenAI-shaped response had no image output: {:?}", value);
            Status::new(Code::Internal, "openai_no_image_returned")
        })?;
    let bytes = STANDARD
        .decode(data)
        .map_err(|_| Status::new(Code::Internal, "openai_invalid_image_data"))?;
    let tokens_used = value["usage"]["total_tokens"].as_i64();
    Ok(OpenAiGeneratedImage { content_type: "image/png".to_string(), bytes, tokens_used })
}
