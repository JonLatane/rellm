module Components.AIProviders exposing
    ( createAIProvider
    , deleteAIProvider
    , generateMedia
    , getAIProviders
    , grantAIProvider
    , hasAnyImageCapability
    , hasImageEditingCapability
    , hasImageGenerationCapability
    , revokeAIProvider
    , updateAIProvider
    )

{-| RPC wrappers for `AIProvider`/`AIProviderGrant` (`protos/ai_providers.proto`)
-- mirrors `Components.SyncSources` in shape exactly: each takes the calling account/server as
an `AccountsPanel.MaybeAccountServer` and returns a `Task` resolving to
`( Maybe AccountsPanel.Msg, response )`, so a token refresh mid-request can still be forwarded on by
the caller (see `Shared.AccountsPanel.performWithAccountServer`).

`UserProfilePage` no longer fetches `AIProvider`s/`AIModel`s on its own initial load
(it reads `User.ai_models`, already carried by the resolved `User` -- see
`AIProvidersState`'s own doc), and every mutation now triggers a full `refetch` of that `User`.
`getAIProviders` is still used, though -- by that section's manual "Refresh" button
(`AIProvidersRefreshClicked`), which overlays just the fresh `providers`/`aiModels`
onto the resolved `User` without a whole-profile refetch.

-}

import Grpc
import Proto.Rellm
    exposing
        ( AIModel
        , AIProvider
        , AIProviderGrant
        , GenerateMediaRequest
        , GetAIProvidersResponse
        , GrantAIProviderRequest
        , Media
        , RevokeAIProviderRequest
        , defaultUser
        )
import Proto.Rellm.AIModelCapability exposing (AIModelCapability(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Task exposing (Task)


{-| `targetUserId = ""` asks the backend for the caller's own providers (see
`backend/src/rpcs/ai_providers/get_ai_providers.rs`); any other id asks for that user's
providers instead, which only succeeds for an Admin caller.
-}
getAIProviders :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetAIProvidersResponse )
getAIProviders accountsPanelModel maybeAccountServer targetUserId =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getAIProviders { defaultUser | id = targetUserId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Always creates a provider owned by the calling account -- the backend ignores/overrides any
`owner` sent (see `create_ai_provider.rs`), so there's no `targetUserId` parameter here
unlike `getAIProviders`.
-}
createAIProvider :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> AIProvider
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, AIProvider )
createAIProvider accountsPanelModel maybeAccountServer provider =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.createAIProvider provider
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


updateAIProvider :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> AIProvider
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, AIProvider )
updateAIProvider accountsPanelModel maybeAccountServer provider =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.updateAIProvider provider
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


deleteAIProvider :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> AIProvider
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteAIProvider accountsPanelModel maybeAccountServer provider =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteAIProvider { provider = Just provider }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| Grants (or resets) `granteeUserId`'s access to `providerId`, owned by the calling account.
Owner-only server-side -- see `RevokeAIProvider`'s own doc comment in
`ai_providers.proto` on why there's no Admin override.
-}
grantAIProvider :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> GrantAIProviderRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, AIProviderGrant )
grantAIProvider accountsPanelModel maybeAccountServer request =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.grantAIProvider request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


revokeAIProvider :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> RevokeAIProviderRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
revokeAIProvider accountsPanelModel maybeAccountServer request =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.revokeAIProvider request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| Generates (or edits, given reference `mediaIds`) an image via one of the calling account's
`AIModel`s -- see `GenerateMediaRequest`'s own doc (`ai_providers.proto`). Used by
`Shared.MediaGeneratorPanel`.
-}
generateMedia :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> GenerateMediaRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Media )
generateMedia accountsPanelModel maybeAccountServer request =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.generateMedia request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Whether `available` can edit an existing image (given one or more reference images plus a
prompt) -- `AIModel.capabilities` is the server's own hardcoded catalog for the model (see
`AIModelCapability`'s own doc, `ai_providers.proto`), not anything this frontend infers from
`modelName` itself. `Shared.MediaGeneratorPanel`'s own model chooser filters down to only these once
the user has picked any reference media (`GenerateMedia`'s own `AI_MODEL_CAPABILITY_IMAGE_EDITING`
requirement in that case) -- see `hasImageGenerationCapability`'s own doc for the no-reference-media
case.
-}
hasImageEditingCapability : AIModel -> Bool
hasImageEditingCapability available =
    List.member AIMODELCAPABILITYIMAGEEDITING available.capabilities


{-| `hasImageEditingCapability`'s counterpart for plain text-to-image generation (no reference
media) -- some models (e.g. `gemini-3.1-flash-lite-image`, the cheaper/faster Gemini tier) only
support this, not editing. `Shared.MediaGeneratorPanel`'s model chooser uses this instead of
`hasImageEditingCapability` whenever its own `media` selection is empty, and reactively re-filters
(re-picking `selectedModel` if it's no longer valid) the moment that changes either way.
-}
hasImageGenerationCapability : AIModel -> Bool
hasImageGenerationCapability available =
    List.member AIMODELCAPABILITYIMAGEGENERATION available.capabilities


{-| Whether `available` is usable by `GenerateMedia` at all, in _either_ mode -- editing (given
reference media) or plain generation (given none). Used to gate whether a Post/Event's
"Generate Media…" button appears at all (`Components.Posts.generateMediaButton`'s callers) --
broader than either capability alone, since a generation-only model is still perfectly usable there
as long as the user doesn't go on to pick any reference media in the panel it opens.
-}
hasAnyImageCapability : AIModel -> Bool
hasAnyImageCapability available =
    hasImageEditingCapability available || hasImageGenerationCapability available
