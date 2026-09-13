use std::collections::HashMap;

use chrono::{DateTime, Utc};
use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    build_occasion_message, build_post_message, capabilities_for_model, generate_image,
    models_for_provider, openai_generate_image, update_media_storage_used, OccasionMessageInput,
    GeminiImageInput, OpenAiImageInput, PostMessageInput,
};
use crate::marshaling::*;
use crate::models;
use crate::models::POST_COLUMNS;
use crate::protos::*;
use crate::rpcs::{get_server_configuration_proto, validate_any_permission, validate_permission};
use crate::schema::{ai_provider_grants, media, posts};

const OPENAI_BASE_URL: &str = "https://api.openai.com";
const DIGITALOCEAN_BASE_URL: &str = "https://inference.do-ai.run";

// Pre-flight input-token estimate constants -- see their one use, below.
const CHARS_PER_TOKEN_ESTIMATE: usize = 4;
const IMAGE_TOKEN_ESTIMATE: i64 = 258;

/// Generates (or edits, given reference `media_ids`) an image via one of the current user's
/// [`AIModel`](#rellm-AIModel)s, stores it as a new `Media`, and -- if `target`
/// is set -- prepends it to that Post's (or Event's own Post's) `media`. See `GenerateMediaRequest`'s
/// own doc for the full shape.
pub async fn generate_media(
    request: GenerateMediaRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<Media, Status> {
    let requested_model = request
        .model
        .ok_or_else(|| Status::new(Code::InvalidArgument, "model_required"))?;
    let provider_id = requested_model
        .provider
        .ok_or_else(|| Status::new(Code::InvalidArgument, "model_provider_required"))?
        .id
        .to_db_id_or_err("model.provider.id")?;
    let model_name = requested_model.model_name.trim().to_string();
    if model_name.is_empty() {
        return Err(Status::new(Code::InvalidArgument, "model_name_required"));
    }
    let user_prompt = request.user_prompt.trim().to_string();
    if user_prompt.is_empty() {
        return Err(Status::new(Code::InvalidArgument, "user_prompt_required"));
    }
    // Parsed up front (not down by `load_reference_images`, its only other use) since which
    // `AiModelCapability` the chosen model needs depends on whether this is empty -- see the
    // capability check below.
    let media_ids: Vec<i64> = request
        .media_ids
        .iter()
        .map(|id| id.to_db_id_or_err("media_ids"))
        .collect::<Result<_, _>>()?;

    let provider = models::get_ai_provider(provider_id, conn)?;
    let provider_proto = provider_configuration_to_proto(&provider.configuration);
    if !models_for_provider(&provider_proto).iter().any(|m| m.name == model_name) {
        return Err(Status::new(
            Code::InvalidArgument,
            "model_not_supported_by_provider",
        ));
    }
    // Editing (`AI_MODEL_CAPABILITY_IMAGE_EDITING`) is only actually required when there's at least
    // one reference image to edit with -- a bare prompt with no reference media only needs plain
    // generation (`AI_MODEL_CAPABILITY_IMAGE_GENERATION`), which some models support without also
    // supporting editing (see `AiModelCapability`'s own doc, and `ai_model_catalog.rs`'s
    // `IMAGE_GENERATION_ONLY_CAPABILITIES` models). `Shared.MediaGeneratorPanel`'s own model chooser
    // mirrors this exact split client-side, but re-checked here since that's just UI, not enforcement.
    let required_capability = if media_ids.is_empty() {
        AiModelCapability::ImageGeneration
    } else {
        AiModelCapability::ImageEditing
    };
    if !capabilities_for_model(&provider_proto, &model_name).contains(&required_capability) {
        return Err(Status::new(
            Code::InvalidArgument,
            if media_ids.is_empty() {
                "model_does_not_support_image_generation"
            } else {
                "model_does_not_support_image_editing"
            },
        ));
    }
    let api_key = match &provider_proto {
        Some(ai_provider::Provider::GeminiCredentials(_)) => {
            gemini_api_key_from_configuration(&provider.configuration)
                .ok_or_else(|| Status::new(Code::Internal, "invalid_provider_configuration"))?
        }
        Some(ai_provider::Provider::OpenaiCredentials(_)) => {
            openai_api_key_from_configuration(&provider.configuration)
                .ok_or_else(|| Status::new(Code::Internal, "invalid_provider_configuration"))?
        }
        Some(ai_provider::Provider::DigitaloceanCredentials(_)) => {
            digitalocean_api_key_from_configuration(&provider.configuration)
                .ok_or_else(|| Status::new(Code::Internal, "invalid_provider_configuration"))?
        }
        _ => {
            return Err(Status::new(
                Code::InvalidArgument,
                "ai_provider_not_yet_supported",
            ))
        }
    };

    // Re-derives the caller's actual access from `provider_id` + `current_user`, rather than
    // trusting anything else the request sent under `model` (see `GenerateMediaRequest.model`'s
    // own doc) -- the provider's owner always has full, ungated access; anyone else needs an
    // `AIProviderGrant` actually covering `model_name`, with tokens left to spend.
    let is_owner = provider.user_id == current_user.id;
    let grant: Option<models::AIProviderGrant> = if is_owner {
        None
    } else {
        let grant = ai_provider_grants::table
            .filter(ai_provider_grants::ai_provider_id.eq(provider.id))
            .filter(ai_provider_grants::grantee_id.eq(current_user.id))
            .first::<models::AIProviderGrant>(conn)
            .optional()
            .map_err(|e| {
                log::error!("Failed to load AI model provider grant: {:?}", e);
                Status::new(Code::Internal, "failed_to_load_grant")
            })?
            .ok_or_else(|| Status::new(Code::PermissionDenied, "no_access_to_provider"))?;
        if !grant.model_names.is_empty() && !grant.model_names.contains(&model_name) {
            return Err(Status::new(Code::PermissionDenied, "model_not_granted"));
        }
        if grant.tokens_remaining <= 0 {
            return Err(Status::new(Code::FailedPrecondition, "no_tokens_remaining"));
        }
        Some(grant)
    };

    // Shared across every ownership check below (target Post/Event, reference media) -- an Admin
    // overrides all of them, matching every other self-or-Admin RPC in this file.
    let admin = validate_permission(&Some(current_user), Permission::Admin).is_ok();

    // Resolves `target` to (a) the Post whose `media` gets the generated image prepended, and (b)
    // the formatted text folded into the prompt as context -- see `GenerateMediaRequest.target`'s
    // own doc.
    let (attach_post_id, context_text) = match &request.target {
        Some(generate_media_request::Target::PostId(id)) => {
            let post_id = id.to_owned().to_db_id_or_err("post_id")?;
            let post: models::Post = posts::table
                .select(POST_COLUMNS)
                .filter(posts::id.eq(post_id))
                .first(conn)
                .map_err(|_| Status::new(Code::NotFound, "post_not_found"))?;
            if post.user_id != Some(current_user.id) && !admin {
                return Err(Status::new(Code::PermissionDenied, "not_your_post"));
            }
            let post_url = frontend_url(conn, "post", post.id)?;
            let message = build_post_message(PostMessageInput {
                title: &post.title,
                content: &post.content,
                link: &post.link,
                post_url: &post_url,
                media: vec![],
            });
            (Some(post.id), Some(message.text))
        }
        // Named by Occasion, not Event, since that's what a caller is actually looking at (and
        // what supplies the prompt's own date/time/location context) -- see
        // `GenerateMediaRequest.target`'s own proto doc. Each Occasion's own Post can carry its
        // own ownership/moderation/visibility independent of the parent Event's (a single
        // "repetition" of a recurring Event may be reassigned/moderated on its own), so both
        // `event_post`/`occasion_post` are loaded and their title/content combined -- mirroring
        // `rpcs::events::sync_occasion`'s own `combine_title`/`combine_content`/
        // `build_occasion_message` call exactly (down to the Event-first title/content
        // ordering), just duplicated locally rather than reused cross-module (those helpers are
        // private to that RPC).
        Some(generate_media_request::Target::OccasionId(id)) => {
            let occasion_id = id.to_owned().to_db_id_or_err("occasion_id")?;
            let occasion = models::get_occasion(occasion_id, &Some(current_user), conn)?;
            let event = models::get_event(occasion.event_id, &Some(current_user), conn)?;
            let event_post: models::Post = posts::table
                .select(POST_COLUMNS)
                .filter(posts::id.eq(event.post_id))
                .first(conn)
                .map_err(|_| Status::new(Code::NotFound, "event_post_not_found"))?;
            let occasion_post: models::Post = posts::table
                .select(POST_COLUMNS)
                .filter(posts::id.eq(occasion.post_id))
                .first(conn)
                .map_err(|_| Status::new(Code::NotFound, "occasion_post_not_found"))?;
            // The generated image is always attached to the Event's own Post (see this match arm's
            // own doc/`GenerateMediaRequest.target`'s), so that -- not the occasion's own, separate
            // ownership -- is what actually gates this.
            if event_post.user_id != Some(current_user.id) && !admin {
                validate_any_permission(
                    &Some(current_user),
                    vec![Permission::ModeratePosts, Permission::ModerateEvents],
                )?;
            }

            let title = combine_title_or_content(&event_post.title, &occasion_post.title, ": ");
            let content = combine_title_or_content(&event_post.content, &occasion_post.content, "\n\n---\n\n");
            let starts_at: DateTime<Utc> = occasion.starts_at.into();
            let ends_at: DateTime<Utc> = occasion.ends_at.into();
            let location = occasion
                .location
                .as_ref()
                .and_then(|l| l.get("uniformly_formatted_address"))
                .and_then(|v| v.as_str())
                .filter(|a| !a.trim().is_empty())
                .map(str::to_string);
            let timezone = location.as_deref().and_then(crate::logic::resolve_timezone);
            let event_url = frontend_url(conn, "event", occasion.post_id)?;
            let message = build_occasion_message(OccasionMessageInput {
                title: &title,
                content: &content,
                link: &occasion_post.link,
                starts_at,
                ends_at,
                location: &location,
                timezone,
                event_url: &event_url,
                media: vec![],
            });
            (Some(event_post.id), Some(message.text))
        }
        None => (None, None),
    };

    let prompt = match &context_text {
        Some(context_text) if !context_text.trim().is_empty() => format!(
            "{user_prompt}\n\nHere is the context of the Event/Post we are generating this image for:\n\n{context_text}"
        ),
        _ => user_prompt,
    };

    // Reference images, in the order the caller gave them -- see `GenerateMediaRequest.media_ids`'s
    // own doc (`media_ids` itself parsed up top, alongside the capability check that depends on
    // whether it's empty). Every one must actually be owned by `current_user` (or `current_user`
    // must be an Admin) -- unlike the target Post/Event (read access to *those* is already implied
    // by whatever let the caller name them in the first place), this is arbitrary media by id, so
    // ownership is checked explicitly rather than assumed.
    let reference_images = load_reference_images(&media_ids, current_user.id, admin, bucket, conn).await?;

    // A grantee (never the owner -- their own key, their own budget) whose *predicted* input cost
    // alone already exceeds what's left is rejected here, before any real (paid) request is ever
    // sent -- the exact, response-driven spend happens after generation succeeds, below, but that's
    // too late to avoid paying for a call we already know can't be afforded. Deliberately a rough
    // estimate, not an exact per-provider tokenizer: ~4 characters per token is a common heuristic
    // for English text, and `IMAGE_TOKEN_ESTIMATE` reuses Gemini's own documented minimum per-image
    // cost (`ai.google.dev/gemini-api/docs/image-generation`) as a reasonable cross-provider
    // stand-in, since we don't have exact pixel dimensions for reference media on hand to compute
    // any provider's real formula precisely. Only ever under-rejects in the "prompt so short it
    // rounds to 0 estimated tokens" case, which the plain `tokens_remaining <= 0` check above
    // already covers regardless.
    if let Some(grant) = &grant {
        let estimated_input_tokens = (prompt.chars().count() / CHARS_PER_TOKEN_ESTIMATE) as i64
            + (reference_images.len() as i64 * IMAGE_TOKEN_ESTIMATE);
        if estimated_input_tokens > grant.tokens_remaining {
            return Err(Status::new(Code::FailedPrecondition, "insufficient_tokens_for_request"));
        }
    }

    // Dispatches to the right provider's own API -- `api_key`/`model_name` were already validated
    // against `provider_proto`'s variant above, so this can't hit the fallback arm. `tokens_used`
    // is `None` for models that don't report `usage.total_tokens` at all (see `openai_media`'s own
    // doc on `OpenAiGeneratedImage.tokens_used`) -- falls back to a flat 1-token charge below.
    let (generated_content_type, generated_bytes, tokens_used) = match &provider_proto {
        Some(ai_provider::Provider::GeminiCredentials(_)) => {
            let gemini_reference_images: Vec<GeminiImageInput> = reference_images
                .iter()
                .map(|(content_type, bytes)| GeminiImageInput {
                    content_type: content_type.clone(),
                    bytes: bytes.clone(),
                })
                .collect();
            let generated = generate_image(&api_key, &model_name, &prompt, &gemini_reference_images)?;
            (generated.content_type, generated.bytes, generated.tokens_used)
        }
        Some(ai_provider::Provider::OpenaiCredentials(_)) => {
            let openai_reference_images: Vec<OpenAiImageInput> = reference_images
                .iter()
                .map(|(content_type, bytes)| OpenAiImageInput {
                    content_type: content_type.clone(),
                    bytes: bytes.clone(),
                })
                .collect();
            let generated =
                openai_generate_image(OPENAI_BASE_URL, &api_key, &model_name, &prompt, &openai_reference_images)?;
            (generated.content_type, generated.bytes, generated.tokens_used)
        }
        // DigitalOcean's Serverless Inference API is OpenAI-Images-API-shaped (see `openai_media`'s
        // own doc), so this reuses `openai_generate_image` wholesale -- just against DigitalOcean's
        // own `base_url`. `reference_images` is always empty here in practice (DigitalOcean's
        // catalog never grants `AiModelCapability::ImageEditing`, so the capability check above
        // already rejects any request naming `media_ids` for one of its models before this point is
        // ever reached), but `openai_generate_image` handles a non-empty list correctly regardless
        // (it would just 404/error against DigitalOcean's own API, which has no edits endpoint).
        Some(ai_provider::Provider::DigitaloceanCredentials(_)) => {
            let digitalocean_reference_images: Vec<OpenAiImageInput> = reference_images
                .iter()
                .map(|(content_type, bytes)| OpenAiImageInput {
                    content_type: content_type.clone(),
                    bytes: bytes.clone(),
                })
                .collect();
            let generated = openai_generate_image(
                DIGITALOCEAN_BASE_URL,
                &api_key,
                &model_name,
                &prompt,
                &digitalocean_reference_images,
            )?;
            (generated.content_type, generated.bytes, generated.tokens_used)
        }
        _ => return Err(Status::new(Code::InvalidArgument, "ai_provider_not_yet_supported")),
    };

    // Only actually spent once generation succeeds -- `tokens_used` is this call's real cost (the
    // provider's own reported `usage.total_tokens`, or a flat 1-token charge as a last resort for
    // models that don't report one at all, e.g. DigitalOcean's `stable-diffusion-3.5-large`). A
    // raw, parameterized `UPDATE` (rather than Diesel's query builder) so the clamp-to-zero and
    // `overage` bookkeeping happen in one atomic statement -- `GREATEST(tokens_remaining - $1, 0)`
    // clamps the new balance at 0 rather than going negative (`tokens_remaining` is unsigned in the
    // proto, `BIGINT` but never actually negative in the DB either), and
    // `GREATEST($1 - tokens_remaining, 0)` records the shortfall as `overage` whenever this single
    // call costs more than what was left -- see `AIProviderGrant.overage`'s own proto doc.
    // Still guarded on `tokens_remaining > 0` (a grant already fully at 0/in overage can't spend
    // further at all -- see `GenerateMediaRequest`'s own doc on why), so a race with another
    // concurrent generation can't double-spend the same tokens.
    if let Some(grant) = &grant {
        let tokens_used = tokens_used.unwrap_or(1).max(1);
        let updated = diesel::sql_query(
            "UPDATE ai_provider_grants \
             SET tokens_remaining = GREATEST(tokens_remaining - $1, 0), \
                 overage = GREATEST($1 - tokens_remaining, 0), \
                 updated_at = NOW() \
             WHERE id = $2 AND tokens_remaining > 0",
        )
        .bind::<diesel::sql_types::BigInt, _>(tokens_used)
        .bind::<diesel::sql_types::BigInt, _>(grant.id)
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to spend AI model provider grant tokens: {:?}", e);
            Status::new(Code::Internal, "failed_to_spend_token")
        })?;
        if updated == 0 {
            return Err(Status::new(Code::FailedPrecondition, "no_tokens_remaining"));
        }
    }

    let minio_path = format!(
        "user/{}-{}/generated-{}.{}",
        current_user.id,
        current_user.username,
        uuid::Uuid::new_v4(),
        extension_for_content_type(&generated_content_type)
    );
    bucket
        .put_object_with_content_type(&minio_path, &generated_bytes, &generated_content_type)
        .await
        .map_err(|e| {
            log::error!("Failed to upload generated media to MinIO: {:?}", e);
            Status::new(Code::Internal, "failed_to_store_generated_media")
        })?;

    let sizes = vec![models::MediaSize {
        conversion: MediaConversion::Original as i32,
        minio_path,
        content_type: generated_content_type,
        size_bytes: generated_bytes.len() as i64,
        aspect_ratio: None,
    }];

    let new_media = insert_into(media::table)
        .values(&models::NewMedia {
            user_id: Some(current_user.id),
            name: Some("Generated Image".to_string()),
            description: None,
            generated: true,
            visibility: Visibility::GlobalPublic.to_string_visibility(),
            metadata: serde_json::to_value(models::MediaMetadata::default()).unwrap(),
            sizes: serde_json::to_value(sizes).unwrap(),
        })
        .get_result::<models::Media>(conn)
        .map_err(|e| {
            log::error!("Failed to create generated media: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_generated_media")
        })?;

    if let Err(e) = update_media_storage_used(current_user.id, conn) {
        log::error!(
            "Failed to update media_storage_bytes_used for user {}: {:?}",
            current_user.id,
            e
        );
    }

    if let Some(attach_post_id) = attach_post_id {
        let mut existing_media: Vec<Option<i64>> = posts::table
            .select(posts::media)
            .filter(posts::id.eq(attach_post_id))
            .first(conn)
            .map_err(|e| {
                log::error!("Failed to load target post media: {:?}", e);
                Status::new(Code::Internal, "failed_to_load_target_post_media")
            })?;
        existing_media.insert(0, Some(new_media.id));
        update(posts::table.filter(posts::id.eq(attach_post_id)))
            .set(posts::media.eq(existing_media))
            .execute(conn)
            .map_err(|e| {
                log::error!("Failed to attach generated media to post: {:?}", e);
                Status::new(Code::Internal, "failed_to_attach_generated_media")
            })?;
    }

    Ok(new_media.to_proto())
}

/// Preferred order to fetch a reference image in -- medium first (same "cap the payload, the model
/// doesn't need full resolution to reference a photo" reasoning `Components.MediaRenderer`'s own
/// default sizing uses), then progressively less ideal fallbacks (small, then large) before finally
/// the original -- see `resolve_media_size_preferring` (`web/media.rs`) for the same preference-list
/// pattern.
const REFERENCE_IMAGE_SIZE_PREFERENCE: [MediaConversion; 3] = [
    MediaConversion::Medium,
    MediaConversion::Small,
    MediaConversion::Large,
];

/// Downloads every one of `media_ids` (in that exact order) from MinIO for use as reference images
/// -- see `REFERENCE_IMAGE_SIZE_PREFERENCE` for which converted size (or the original, as a last
/// resort) each one is actually fetched at. Returned as plain `(content_type, bytes)` pairs,
/// provider-agnostic, since the caller wraps each into whichever provider-specific input type
/// (`GeminiImageInput`/`OpenAiImageInput`) the chosen `AIProvider` variant actually needs.
///
/// Every id must resolve to a `Media` row owned by `current_user_id` (or `admin` must be `true`) --
/// unlike the target Post/Event, this is arbitrary media named by id, so ownership isn't implied by
/// anything else the caller had to already prove access to. Fails the whole request (rather than
/// silently skipping) on the first id that doesn't resolve or isn't owned, so a caller never gets a
/// generation run against a silently-incomplete reference set.
async fn load_reference_images(
    media_ids: &[i64],
    current_user_id: i64,
    admin: bool,
    bucket: &Bucket,
    conn: &mut PgPooledConnection,
) -> Result<Vec<(String, Vec<u8>)>, Status> {
    if media_ids.is_empty() {
        return Ok(vec![]);
    }
    let rows: Vec<models::Media> = media::table
        .filter(media::id.eq_any(media_ids))
        .load(conn)
        .map_err(|e| {
            log::error!("Failed to load reference media: {:?}", e);
            Status::new(Code::Internal, "failed_to_load_reference_media")
        })?;
    let by_id: HashMap<i64, models::Media> = rows.into_iter().map(|m| (m.id, m)).collect();

    let mut images = Vec::with_capacity(media_ids.len());
    for id in media_ids {
        let Some(row) = by_id.get(id) else {
            return Err(Status::new(Code::NotFound, "reference_media_not_found"));
        };
        if row.user_id != Some(current_user_id) && !admin {
            return Err(Status::new(Code::PermissionDenied, "not_your_media"));
        }
        let sizes = row.sizes();
        let (minio_path, content_type) = REFERENCE_IMAGE_SIZE_PREFERENCE
            .iter()
            .find_map(|conversion| sizes.iter().find(|s| s.conversion == *conversion as i32))
            .or_else(|| sizes.iter().find(|s| s.conversion == MediaConversion::Original as i32))
            .map(|s| (s.minio_path.clone(), s.content_type.clone()))
            .ok_or_else(|| Status::new(Code::NotFound, "reference_media_not_found"))?;
        let bytes = bucket.get_object(&minio_path).await.map_err(|e| {
            log::error!("Failed to download reference media {} from MinIO: {:?}", id, e);
            Status::new(Code::Internal, "failed_to_load_reference_media")
        })?;
        images.push((content_type, bytes.as_slice().to_vec()));
    }
    Ok(images)
}

/// `"{event_title}: {occasion_title}"`/`"{event_content}\n\n---\n\n{occasion_content}"`-shaped
/// combination of an Occasion's own title/content override with its parent Event's, in that
/// order -- mirrors `rpcs::events::sync_occasion`'s own `combine`/`combine_title`/
/// `combine_content` exactly (down to falling back to whichever side is actually set, and `None`
/// when neither is); duplicated locally since those are private to that module. `separator` is `": "`
/// for titles, `"\n\n---\n\n"` for content -- see this function's two call sites.
fn combine_title_or_content(event_side: &Option<String>, occasion_side: &Option<String>, separator: &str) -> Option<String> {
    let event_side = event_side.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let occasion_side = occasion_side.as_deref().map(str::trim).filter(|s| !s.is_empty());
    match (event_side, occasion_side) {
        (Some(e), Some(i)) => Some(format!("{e}{separator}{i}")),
        (Some(e), None) => Some(e.to_string()),
        (None, Some(i)) => Some(i.to_string()),
        (None, None) => None,
    }
}

/// Best-effort `https://{frontend_host}/{kind}/{id}` link back to this Rellm server's own
/// frontend, mirroring `sync_post`/`sync_occasion`'s own `post_url`/`event_url` -- `None` if
/// `external_cdn_config.frontend_host` isn't configured (this RPC has no HTTP `Host` header to fall
/// back on).
fn frontend_url(conn: &mut PgPooledConnection, kind: &str, id: i64) -> Result<Option<String>, Status> {
    let external_cdn_config = get_server_configuration_proto(conn)?.external_cdn_config;
    Ok(external_cdn_config
        .as_ref()
        .map(|c| c.frontend_host.clone())
        .filter(|h| !h.trim().is_empty())
        .map(|host| format!("https://{host}/{kind}/{}", id.to_proto_id())))
}

fn extension_for_content_type(content_type: &str) -> &'static str {
    match content_type {
        "image/png" => "png",
        "image/webp" => "webp",
        "image/gif" => "gif",
        _ => "jpg",
    }
}
