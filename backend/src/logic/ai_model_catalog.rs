//! A static, hand-maintained catalog of the models each `AIProvider.provider` variant
//! supports, and what each one can actually do (see `protos/ai_providers.proto`'s
//! `AIModelCapability`). None of Anthropic/OpenAI/Gemini/DigitalOcean expose a "list models"
//! endpoint stable/simple enough to build `AIModel`s from at request time, so this list is
//! updated by hand as new models ship -- see `models_for_provider`, used by `rpcs::ai_providers`
//! to expand a provider (or a grant's `model_names`) into the `AIModel`s a user can
//! actually see.

use crate::protos::ai_provider::Provider;
use crate::protos::AiModelCapability;

/// One model in the catalog -- a name plus what it can actually do, per `AIModelCapability`'s own
/// doc. `name` is the exact string sent to the provider's own API (`AIModel.model_name`);
/// `capabilities` is what feature gating (e.g. `rpcs::ai_providers::generate_media`, which
/// requires `ImageEditing`) actually checks, rather than hardcoding model names of its own.
pub struct ModelInfo {
    pub name: &'static str,
    pub capabilities: &'static [AiModelCapability],
}

const IMAGE_EDITING_CAPABILITIES: &[AiModelCapability] =
    &[AiModelCapability::ImageGeneration, AiModelCapability::ImageEditing];
const IMAGE_GENERATION_ONLY_CAPABILITIES: &[AiModelCapability] = &[AiModelCapability::ImageGeneration];

/// Gemini API (`ai.google.dev/gemini-api`) image generation/editing models -- the "Nano Banana"
/// family, Rellm's actual near-term use case (generating/editing Event posters). Ordered
/// newest/most-capable first. `gemini-2.5-flash-image` is the original ("legacy") model; Google's
/// own docs now recommend `gemini-3.1-flash-lite-image` for new plain text-to-image work instead.
/// Only `gemini-3-pro-image` and `gemini-3.1-flash-image` support image *editing* (multi-turn,
/// passing a prior image back in as part of the prompt) -- see
/// `ai.google.dev/gemini-api/docs/image-generation#gemini-image-editing`.
pub const GEMINI_MODELS: &[ModelInfo] = &[
    ModelInfo { name: "gemini-3-pro-image", capabilities: IMAGE_EDITING_CAPABILITIES },
    ModelInfo { name: "gemini-3.1-flash-image", capabilities: IMAGE_EDITING_CAPABILITIES },
    ModelInfo { name: "gemini-3.1-flash-lite-image", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
    ModelInfo { name: "gemini-2.5-flash-image", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
];

/// OpenAI's GPT Image family (`platform.openai.com/docs/guides/image-generation`) -- generation via
/// `POST /v1/images/generations`, editing (given one or more reference images) via
/// `POST /v1/images/edits`, both `AiModelCapability::ImageGeneration`/`ImageEditing`-capable like
/// Gemini's own top-tier models. Ordered newest/most-capable first; `gpt-image-1-mini` trades
/// quality for speed/cost, otherwise all four support the same two endpoints.
pub const OPENAI_MODELS: &[ModelInfo] = &[
    ModelInfo { name: "gpt-image-2", capabilities: IMAGE_EDITING_CAPABILITIES },
    ModelInfo { name: "gpt-image-1.5", capabilities: IMAGE_EDITING_CAPABILITIES },
    ModelInfo { name: "gpt-image-1", capabilities: IMAGE_EDITING_CAPABILITIES },
    ModelInfo { name: "gpt-image-1-mini", capabilities: IMAGE_EDITING_CAPABILITIES },
];

/// DigitalOcean's Gradient AI Platform / Serverless Inference (`docs.digitalocean.com/products/inference`) --
/// GPT Image and Stable Diffusion models re-hosted under DigitalOcean's own billing, all reachable through one
/// OpenAI-Images-API-shaped `POST /v1/images/generations` endpoint. Generation-only for every model here: unlike
/// direct OpenAI, DigitalOcean's Serverless Inference API has no `/v1/images/edits`-equivalent endpoint at all
/// (confirmed against its own endpoint list), so none of these carry `AiModelCapability::ImageEditing`, even the
/// `gpt-image-*` models that *do* support editing when called directly against OpenAI's own API instead.
pub const DIGITALOCEAN_MODELS: &[ModelInfo] = &[
    ModelInfo { name: "openai-gpt-image-2", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
    ModelInfo { name: "openai-gpt-image-1.5", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
    ModelInfo { name: "openai-gpt-image-1", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
    ModelInfo { name: "stable-diffusion-3.5-large", capabilities: IMAGE_GENERATION_ONLY_CAPABILITIES },
];

/// Anthropic models -- empty for now, since `AnthropicCredentials` isn't yet accepted by
/// `CreateAIProvider` (see that message's own proto doc).
pub const ANTHROPIC_MODELS: &[ModelInfo] = &[];

/// A friendlier display name for a model, e.g. for `logic::market_summary`'s human-readable
/// `MarketProduct` descriptions -- Rellm's own "Nano Banana" nicknames for the Gemini image family
/// (see `GEMINI_MODELS`'s own doc), falling back to the raw provider-API model name for every
/// other model, which has no comparable nickname in common use.
pub fn display_name(model_name: &str) -> String {
    match model_name {
        "gemini-3-pro-image" => "Nano Banana Pro".to_string(),
        "gemini-3.1-flash-image" => "Nano Banana Flash".to_string(),
        "gemini-3.1-flash-lite-image" => "Nano Banana Flash Lite".to_string(),
        "gemini-2.5-flash-image" => "Nano Banana".to_string(),
        other => other.to_string(),
    }
}

/// Every model `provider`'s external service supports, regardless of any grant -- the full set an
/// owner sees. `None` (an unset `oneof`) has no models.
pub fn models_for_provider(provider: &Option<Provider>) -> &'static [ModelInfo] {
    match provider {
        Some(Provider::GeminiCredentials(_)) => GEMINI_MODELS,
        Some(Provider::OpenaiCredentials(_)) => OPENAI_MODELS,
        Some(Provider::AnthropicCredentials(_)) => ANTHROPIC_MODELS,
        Some(Provider::DigitaloceanCredentials(_)) => DIGITALOCEAN_MODELS,
        None => &[],
    }
}

/// `capabilities` for one named model of `provider`'s catalog -- empty if `provider`/`model_name`
/// don't match anything known (e.g. a grant's `model_names` naming a model that's since been
/// dropped from the catalog). Used by `rpcs::ai_providers::generate_media` to check
/// `AiModelCapability::ImageEditing` without re-deriving a whole `AIModel` first.
pub fn capabilities_for_model(provider: &Option<Provider>, model_name: &str) -> &'static [AiModelCapability] {
    models_for_provider(provider)
        .iter()
        .find(|model| model.name == model_name)
        .map(|model| model.capabilities)
        .unwrap_or(&[])
}
