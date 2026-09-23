module Components.Pages.ServerInformationPage.ClusterTab exposing (Model, Msg, activated, init, update, view)

{-| The Cluster tab of `Components.Pages.ServerInformationPage` -- `ClusterResources` (see that
message's own doc in `server_configuration.proto`), editable by an admin holding
`EDITCLUSTERSETTINGS` as one unit (a single Edit/Save/Cancel, like every other section on this
page). Unlike every other tab, this one is never shown to a non-admin at all (see
`Components.Pages.ServerInformationPage`'s own tab list) -- `cluster_resources` is stripped
server-side from `GetServerConfiguration` for anyone but an admin, so there'd be nothing to show.

Within the tab, a _plain_ admin (no `EDITCLUSTERSETTINGS`) still sees the current settings, just
without an Edit button -- mirroring `Common.adminAccountFor`'s "view vs. edit" split one permission
level further in, the same way `CdnTab`'s `cdnGrpc` field is always shown but never editable yet.
`clusterSharedSecret` is write-only (never sent back by the server, same as
`FacebookAuthConfig.appSecret`) -- its edit field always starts blank, and blank-on-save means
"leave the stored secret alone."

Unlike every other tab here, this one can't just read `RellmServers.configurationOf server` for its
display -- that cache comes from `RellmServers.negotiateRellmServerConfig`'s unauthenticated
`GetServerConfiguration` probe (used for the initial "can we connect at all" check and every
reconnect), and `cluster_resources` is stripped from that unauthenticated response entirely (see
above). So whenever an admin account is present, this tab fires its own authenticated
`GetServerConfiguration` (`fetchAuthenticatedServerConfiguration`/`AdminClusterResourcesStatus`) and
displays _that_ instead, via the exposed `activated` message.

`activated`'s own fetch resolves `targetHost` against `Shared.AccountsPanel`'s _live_ connection
state, which isn't necessarily settled yet the moment this tab first becomes relevant -- in
particular, a persisted account's server reconnects asynchronously on app startup (mirrors
`Components.Pages.PostsPage.fetchNewFeeds`'s own doc on the identical problem for feeds), and that
reconnect can genuinely take a while. Firing too early doesn't just miss a beat -- `resolveAccountServer`
fails outright and the fetch comes back `Grpc.NetworkError`, indistinguishable by
`Shared.AccountsPanel.grpcErrorToString`'s bare string from a real network failure. So, like
`fetchNewFeeds`, this doesn't try to time one perfect fetch: `Components.Pages.ServerInformationPage`
dispatches `activated` from every point its own connectivity state could plausibly have changed --
`TabSelected`, `GotOwnServerResult`'s success branch, `init`'s already-known-connected branch, _and_
every `SharedMsg` (any `AccountsPanel` change at all, including that startup reconnect finishing) --
via `activateClusterTab`. `ClusterTabActivated`'s own handler makes that safe to call as often as it
likes: it only actually fetches from `AdminClusterResourcesNotFetched`/`AdminClusterResourcesFetchFailed`,
so a `SharedMsg` firing after a lock's already loaded is a cheap no-op, not a repeat fetch.

-}

import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, hr, input, span, text)
import Html.Attributes exposing (class, disabled, href, placeholder, target, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Google.Protobuf exposing (Empty)
import Proto.Rellm exposing (ClusterConductorState, ClusterResourceLimit, ClusterResourceLock, ClusterResources, ExternalCDNConfig, ServerConfiguration, defaultClusterConductorState, defaultClusterResources)
import Proto.Rellm.ClusterResource exposing (ClusterResource(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.Rellm as Rellm
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Conversions exposing (timestampToPosix)
import Shared.Time as SharedTime
import Task



-- MODEL


type alias Model =
    { configEdit : Maybe ClusterConfigEdit
    , limitsEdit : Maybe LimitsEdit
    , adminClusterResources : AdminClusterResourcesStatus
    , freeingLock : Maybe FreeingLock
    , freeLockError : Maybe String
    }


{-| Identifies which `Free <resource> held by <namespaceId>` button (see `freeButton`) is
currently in flight -- there's at most one at a time (every other one is `disabled` while this is
set, see `freeButton`), but which one it is still matters for showing "Freeing…" on the right
button rather than all of them.
-}
type alias FreeingLock =
    { namespaceId : String
    , resource : ClusterResource
    }


{-| The result of this tab's own authenticated `GetServerConfiguration` fetch -- see this module's
own doc for why it can't just read `RellmServers.configurationOf server` like every other tab.
`AdminClusterResourcesLoaded` holds the fetched `clusterResources` directly (already `Nothing` if
genuinely unset -- indistinguishable from "not fetched yet" by value alone, hence this being its
own status type rather than a bare `Maybe (Maybe ClusterResources)`).
-}
type AdminClusterResourcesStatus
    = AdminClusterResourcesNotFetched
    | FetchingAdminClusterResources
    | AdminClusterResourcesLoaded (Maybe ClusterResources)
    | AdminClusterResourcesFetchFailed String


type Msg
    = ClusterEditClicked
    | ClusterEnabledToggled
    | ClusterNamespaceIdChanged String
    | ClusterConductorHostChanged String
    | ClusterSharedSecretChanged String
    | ClusterCancelClicked
    | ClusterSaveClicked
    | GotClusterSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | ClusterTabActivated
    | GotAuthenticatedServerConfiguration (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | FreeLockClicked String ClusterResource
    | GotFreeLockResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Empty ))
    | LimitsEditClicked
    | LimitsBrowserChanged String
    | LimitsFfmpegChanged String
    | LimitsImagemagickChanged String
    | LimitsCancelClicked
    | LimitsSaveClicked
    | GotLimitsSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


{-| Live only while the cluster config is being edited -- `enabled` mirrors whether
`clusterResources` itself should be `Just`/`Nothing` on save (see `applyClusterConfig`);
`namespaceId`/`conductorHost`/`sharedSecret` are only meaningful (and only enabled in
`clusterEditView`) while `enabled` is `True`. `sharedSecret` always starts blank -- see this
module's own doc.
-}
type alias ClusterConfigEdit =
    { enabled : Bool
    , namespaceId : String
    , conductorHost : String
    , sharedSecret : String
    , status : AccountsPanel.FormStatus
    }


{-| Live only while `ClusterConductorState.limits` is being edited -- a separate Edit/Save/Cancel
from `ClusterConfigEdit` above (its own "Edit Limits" button, see `clusterDisplayView`), since
`limits` is meaningful with or without cluster resource sharing itself being configured yet. Each
field is the resource's own concurrency limit (0-10, see `limitInput`), defaulting to `1` (see
`effectiveLimit`) the same way the server itself treats an unconfigured resource.
-}
type alias LimitsEdit =
    { browser : Int
    , ffmpeg : Int
    , imagemagick : Int
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { configEdit = Nothing
    , limitsEdit = Nothing
    , adminClusterResources = AdminClusterResourcesNotFetched
    , freeingLock = Nothing
    , freeLockError = Nothing
    }


{-| `Components.Pages.ServerInformationPage` dispatches this (via `ClusterTab.update`) whenever
this tab becomes the active one -- on `TabSelected TabCluster`, and at `init` for a reload/deep
link landing directly on it -- to kick off the authenticated fetch this module's own doc describes.
`ClusterTabActivated`'s constructor itself isn't exposed (like every other `Msg` here), so this is
the one blessed way a parent triggers it.
-}
activated : Msg
activated =
    ClusterTabActivated



-- UPDATE


update : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost msg model =
    case msg of
        ClusterEditClicked ->
            let
                clusterResources : Maybe ClusterResources
                clusterResources =
                    case model.adminClusterResources of
                        AdminClusterResourcesLoaded resources ->
                            resources

                        _ ->
                            Nothing
            in
            ( { model
                | configEdit =
                    Just
                        { enabled = clusterResources /= Nothing
                        , namespaceId = clusterResources |> Maybe.map .namespaceId |> Maybe.withDefault ""
                        , conductorHost = clusterResources |> Maybe.map .conductorHost |> Maybe.withDefault ""
                        , sharedSecret = ""
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        ClusterEnabledToggled ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        ClusterNamespaceIdChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | namespaceId = text }) }, Effect.none )

        ClusterConductorHostChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | conductorHost = text }) }, Effect.none )

        ClusterSharedSecretChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | sharedSecret = text }) }, Effect.none )

        ClusterCancelClicked ->
            ( { model | configEdit = Nothing }, Effect.none )

        ClusterSaveClicked ->
            case ( model.configEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | configEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyClusterConfig edit)
                        |> Task.attempt GotClusterSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotClusterSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | configEdit = Nothing, adminClusterResources = AdminClusterResourcesLoaded newConfig.clusterResources }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotClusterSaveResult (Err err) ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        ClusterTabActivated ->
            case ( model.adminClusterResources, Common.adminAccountFor shared targetHost ) of
                ( AdminClusterResourcesNotFetched, Just account ) ->
                    ( { model | adminClusterResources = FetchingAdminClusterResources }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                ( AdminClusterResourcesFetchFailed _, Just account ) ->
                    ( { model | adminClusterResources = FetchingAdminClusterResources }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                _ ->
                    ( model, Effect.none )

        GotAuthenticatedServerConfiguration (Ok ( maybeAccountsPanelMsg, config )) ->
            ( { model | adminClusterResources = AdminClusterResourcesLoaded config.clusterResources }
            , Common.accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAuthenticatedServerConfiguration (Err err) ->
            ( { model | adminClusterResources = AdminClusterResourcesFetchFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        FreeLockClicked namespaceId resource ->
            case ( model.freeingLock, Common.adminAccountFor shared targetHost ) of
                ( Nothing, Just account ) ->
                    ( { model | freeingLock = Just { namespaceId = namespaceId, resource = resource }, freeLockError = Nothing }
                    , freeClusterResource shared targetHost account namespaceId resource
                    )

                _ ->
                    ( model, Effect.none )

        GotFreeLockResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            case Common.adminAccountFor shared targetHost of
                Just account ->
                    ( { model | freeingLock = Nothing, adminClusterResources = FetchingAdminClusterResources }
                    , Effect.batch
                        [ Common.accountsPanelEffect maybeAccountsPanelMsg
                        , fetchAuthenticatedServerConfiguration shared targetHost account
                        ]
                    )

                Nothing ->
                    ( { model | freeingLock = Nothing }, Common.accountsPanelEffect maybeAccountsPanelMsg )

        GotFreeLockResult (Err err) ->
            ( { model | freeingLock = Nothing, freeLockError = Just (AccountsPanel.grpcErrorToString err) }, Effect.none )

        LimitsEditClicked ->
            let
                limits : List ClusterResourceLimit
                limits =
                    case model.adminClusterResources of
                        AdminClusterResourcesLoaded (Just resources) ->
                            resources.conductorState |> Maybe.map .limits |> Maybe.withDefault []

                        _ ->
                            []
            in
            ( { model
                | limitsEdit =
                    Just
                        { browser = effectiveLimit limits CLUSTERRESOURCEBROWSER
                        , ffmpeg = effectiveLimit limits CLUSTERRESOURCEFFMPEG
                        , imagemagick = effectiveLimit limits CLUSTERRESOURCEIMAGEMAGICK
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        LimitsBrowserChanged text ->
            ( { model | limitsEdit = model.limitsEdit |> Maybe.map (\edit -> { edit | browser = clampedLimit text edit.browser }) }, Effect.none )

        LimitsFfmpegChanged text ->
            ( { model | limitsEdit = model.limitsEdit |> Maybe.map (\edit -> { edit | ffmpeg = clampedLimit text edit.ffmpeg }) }, Effect.none )

        LimitsImagemagickChanged text ->
            ( { model | limitsEdit = model.limitsEdit |> Maybe.map (\edit -> { edit | imagemagick = clampedLimit text edit.imagemagick }) }, Effect.none )

        LimitsCancelClicked ->
            ( { model | limitsEdit = Nothing }, Effect.none )

        LimitsSaveClicked ->
            case ( model.limitsEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | limitsEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyLimitsConfig edit)
                        |> Task.attempt GotLimitsSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotLimitsSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | limitsEdit = Nothing, adminClusterResources = AdminClusterResourcesLoaded newConfig.clusterResources }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotLimitsSaveResult (Err err) ->
            ( { model | limitsEdit = model.limitsEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )


{-| `cluster_resources` is stripped from the unauthenticated `GetServerConfiguration` every other
tab reads via `RellmServers.configurationOf` (see this module's own doc) -- this fetches it fresh,
authenticated as `account`, the same way `AccountsPanel.updateServerConfig` does before writing.
-}
fetchAuthenticatedServerConfiguration : Shared.Model -> String -> RellmAccount -> Effect Msg
fetchAuthenticatedServerConfiguration shared targetHost account =
    AccountsPanel.performWithAccountServer shared.accounts
        ( Just account.userId, targetHost )
        (\server token ->
            Grpc.new Rellm.getServerConfiguration {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> RellmServers.withAccessToken (Just token)
                |> Grpc.toTask
        )
        |> Task.attempt GotAuthenticatedServerConfiguration
        |> Effect.fromCmd


{-| Calls `FreeClusterResources`, authenticated as `account` -- see that RPC's own doc on why an
`EDIT_CLUSTER_SETTINGS` admin can free _any_ namespace's lock this way (`namespaceId` here is the
lock's holder, not necessarily `account`'s own), unlike the cluster-internal
`cluster-shared-secret` path `generate_preview_images` itself uses.
-}
freeClusterResource : Shared.Model -> String -> RellmAccount -> String -> ClusterResource -> Effect Msg
freeClusterResource shared targetHost account namespaceId resource =
    AccountsPanel.performWithAccountServer shared.accounts
        ( Just account.userId, targetHost )
        (\server token ->
            Grpc.new Rellm.freeClusterResources { namespaceId = namespaceId, resources = [ resource ] }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> RellmServers.withAccessToken (Just token)
                |> Grpc.toTask
        )
        |> Task.attempt GotFreeLockResult
        |> Effect.fromCmd


{-| `ClusterSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way
every other editor's transform is -- when `enabled` is off, nulls `clusterResources` out entirely;
when on, overlays `namespaceId`/`conductorHost` onto whatever a freshly re-fetched config already
has for `clusterResources` (`defaultClusterResources` the first time it's ever set). `sharedSecret`
is sent blank unless this save is actually changing it (edit.sharedSecret non-empty) -- a blank
incoming value means "leave the stored secret alone" server-side, same as `applyFacebookAppSecret`.
`conductorState` is left untouched either way -- the server never lets `ConfigureServer` change it
regardless of what's sent (see `ClusterResources.conductorState`'s own doc).
-}
applyClusterConfig : ClusterConfigEdit -> ServerConfiguration -> ServerConfiguration
applyClusterConfig edit config =
    if edit.enabled then
        let
            existing : ClusterResources
            existing =
                Maybe.withDefault defaultClusterResources config.clusterResources
        in
        { config
            | clusterResources =
                Just
                    { existing
                        | namespaceId = edit.namespaceId
                        , conductorHost = edit.conductorHost
                        , clusterSharedSecret = edit.sharedSecret
                    }
        }

    else
        { config | clusterResources = Nothing }


{-| Parses `text` as an `Int` and clamps it to the 0-10 range `limitInput`'s HTML `min`/`max`
advertise, falling back to `fallback` (the field's current value) if `text` doesn't parse at all --
e.g. the instant a user clears the input to type a new number. See `limitInput`'s own doc for why
that fallback never actually traps the user.
-}
clampedLimit : String -> Int -> Int
clampedLimit text fallback =
    text |> String.toInt |> Maybe.map (clamp 0 10) |> Maybe.withDefault fallback


{-| `resource`'s configured concurrency limit within `limits`, defaulting to `1` if `resource`
isn't present at all -- the client-side mirror of the server's own `effective_limit` (in
`lock_cluster_resources.rs`). Zips each `ClusterResourceLimit`'s parallel `resource`/`limit` lists
by position (see that message's own doc for why they're parallel lists rather than one
`resource`/`limit` pair per message) and looks for `resource` among the pairs.
-}
effectiveLimit : List ClusterResourceLimit -> ClusterResource -> Int
effectiveLimit limits resource =
    limits
        |> List.concatMap (\entry -> List.map2 Tuple.pair entry.resource entry.limit)
        |> List.filter (\( r, _ ) -> r == resource)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault 1


{-| `LimitsSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way
`applyClusterConfig` is -- overlays `edit`'s three limits onto whatever a freshly re-fetched config
already has for `clusterResources.conductorState` (`defaultClusterResources`/
`defaultClusterConductorState` the first time either is ever set), leaving every other field
(`namespaceId`/`conductorHost`/`clusterSharedSecret`/`locks`) untouched. Always writes all three
`ClusterResourceLimit` entries, even ones still at the default `1` -- once a user has actually
opened "Edit Limits" and saved, an explicit `1` is clearer than omitting it.
-}
applyLimitsConfig : LimitsEdit -> ServerConfiguration -> ServerConfiguration
applyLimitsConfig edit config =
    let
        existing : ClusterResources
        existing =
            Maybe.withDefault defaultClusterResources config.clusterResources

        conductorState : ClusterConductorState
        conductorState =
            Maybe.withDefault defaultClusterConductorState existing.conductorState

        limits : List ClusterResourceLimit
        limits =
            [ { resource = [ CLUSTERRESOURCEBROWSER ], limit = [ edit.browser ] }
            , { resource = [ CLUSTERRESOURCEFFMPEG ], limit = [ edit.ffmpeg ] }
            , { resource = [ CLUSTERRESOURCEIMAGEMAGICK ], limit = [ edit.imagemagick ] }
            ]
    in
    { config | clusterResources = Just { existing | conductorState = Just { conductorState | limits = limits } } }



-- VIEW


{-| Whether `account` can actually edit `clusterResources` via `ConfigureServer` -- `ADMIN` alone
(already required just to reach this tab -- see this module's own doc) isn't enough; the server
also requires `EDITCLUSTERSETTINGS` specifically (see that permission's own doc), deliberately not
grantable via `UpdateUser`, so this can't be self-served the way most permissions can.
-}
canEditCluster : RellmAccount -> Bool
canEditCluster account =
    List.member EDITCLUSTERSETTINGS account.permissions


view : Shared.Model -> RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view shared server maybeAdminAccount model =
    div [ class "server-details-tab-content server-details-cluster" ]
        (case model.adminClusterResources of
            FetchingAdminClusterResources ->
                [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

            AdminClusterResourcesFetchFailed err ->
                [ span [ class "server-details-feature-settings-value" ] [ text ("Failed to load cluster settings: " ++ err) ] ]

            adminClusterResources ->
                let
                    clusterResources : Maybe ClusterResources
                    clusterResources =
                        case adminClusterResources of
                            AdminClusterResourcesLoaded resources ->
                                resources

                            _ ->
                                Nothing
                in
                clusterSectionsView shared.time maybeAdminAccount clusterResources (RellmServers.configurationOf server).externalCdnConfig model
        )


{-| The tab's three fixed sections, always laid out in this order (never swapped out for one
another the way an in-progress edit used to replace the _entire_ tab body) -- "Cluster settings"
(with its own "Edit Cluster Settings" button right under "Conductor Host"), then "Held Locks", then
"Limits" (with its own "Edit Limits" button), each separated by an `hr`. "Held Locks"/"Limits" --
and the `hr`s around them -- only exist at all when `conductorState` is populated, i.e. only on the
instance that's actually the conductor (see `ClusterResources.conductorState`'s own doc) -- a
non-conductor instance simply has nothing there to show or edit, not something being conditionally
hidden mid-layout.
-}
clusterSectionsView : SharedTime.Model -> Maybe RellmAccount -> Maybe ClusterResources -> Maybe ExternalCDNConfig -> Model -> List (Html Msg)
clusterSectionsView time maybeAdminAccount clusterResources externalCdnConfig model =
    let
        canEdit : Bool
        canEdit =
            maybeAdminAccount |> Maybe.map canEditCluster |> Maybe.withDefault False
    in
    List.concat
        [ clusterSettingsSection canEdit clusterResources externalCdnConfig model.configEdit
        , case clusterResources |> Maybe.andThen .conductorState of
            Just conductorState ->
                List.concat
                    [ [ hr [] [] ]
                    , locksSection time canEdit model.freeingLock model.freeLockError conductorState.locks
                    , [ hr [] [] ]
                    , limitsSection canEdit conductorState.limits model.limitsEdit
                    ]

            Nothing ->
                []
        ]


{-| "Cluster Resource Sharing"/"Namespace ID"/"Conductor Host", with "Edit Cluster Settings" right
below them -- or, while `configEdit` is active, `clusterEditView` in their place.
-}
clusterSettingsSection : Bool -> Maybe ClusterResources -> Maybe ExternalCDNConfig -> Maybe ClusterConfigEdit -> List (Html Msg)
clusterSettingsSection canEdit clusterResources externalCdnConfig configEdit =
    case configEdit of
        Just edit ->
            clusterEditView edit

        Nothing ->
            [ Common.settingsRow "Cluster Resource Sharing" (Common.switchDisplay (clusterResources /= Nothing))
            , Common.settingsRow "Namespace ID" (span [ class "server-details-feature-settings-value" ] [ text (clusterResources |> Maybe.map .namespaceId |> Maybe.withDefault "—") ])
            , Common.settingsRow "Conductor Host" (conductorHostView clusterResources externalCdnConfig)
            , if canEdit then
                div [ class "server-details-feature-settings-actions" ]
                    [ button [ class "server-details-rename-button", onClick ClusterEditClicked ] [ text "Edit Cluster Settings" ] ]

              else
                text ""
            ]


locksSection : SharedTime.Model -> Bool -> Maybe FreeingLock -> Maybe String -> List ClusterResourceLock -> List (Html Msg)
locksSection time canEdit freeingLock freeLockError locks =
    [ Common.settingsRow "Held Locks" (heldLocksView time canEdit freeingLock locks)
    , case freeLockError of
        Just err ->
            span [ class "server-details-rename-error" ] [ text ("Failed to free lock: " ++ err) ]

        Nothing ->
            text ""
    ]


{-| "Browser Instance Limit"/"FFMPEG Process Limit"/"ImageMagick Process Limit", with "Edit
Limits" below them -- or, while `limitsEdit` is active, `limitsEditView` in their place.
-}
limitsSection : Bool -> List ClusterResourceLimit -> Maybe LimitsEdit -> List (Html Msg)
limitsSection canEdit limits limitsEdit =
    case limitsEdit of
        Just edit ->
            limitsEditView edit

        Nothing ->
            [ Common.settingsRow "Browser Instance Limit" (span [ class "server-details-feature-settings-value" ] [ text (String.fromInt (effectiveLimit limits CLUSTERRESOURCEBROWSER)) ])
            , Common.settingsRow "FFMPEG Process Limit" (span [ class "server-details-feature-settings-value" ] [ text (String.fromInt (effectiveLimit limits CLUSTERRESOURCEFFMPEG)) ])
            , Common.settingsRow "ImageMagick Process Limit" (span [ class "server-details-feature-settings-value" ] [ text (String.fromInt (effectiveLimit limits CLUSTERRESOURCEIMAGEMAGICK)) ])
            , if canEdit then
                div [ class "server-details-feature-settings-actions" ]
                    [ button [ class "server-details-rename-button", onClick LimitsEditClicked ] [ text "Edit Limits" ] ]

              else
                text ""
            ]


{-| Plain text for "—" (unset), for this instance itself being the conductor (`conductorState` is
populated -- see that field's own doc), or for a conductor that's simply this same server (matching
its own `ExternalCDNConfig`, if any -- linking to yourself is pointless). Otherwise, a link to that
other instance's own Cluster tab (`{conductor_host}/about?tab=cluster`) -- useful since checking a
lock's `acquired_at` (`Held Locks` above) only ever works from the conductor's own tab.
-}
conductorHostView : Maybe ClusterResources -> Maybe ExternalCDNConfig -> Html Msg
conductorHostView clusterResources externalCdnConfig =
    let
        conductorHost : String
        conductorHost =
            clusterResources |> Maybe.map .conductorHost |> Maybe.withDefault ""
    in
    if conductorHost == "" then
        span [ class "server-details-feature-settings-value" ] [ text "—" ]

    else
        let
            isThisInstance : Bool
            isThisInstance =
                (clusterResources |> Maybe.andThen .conductorState)
                    /= Nothing
                    || (case externalCdnConfig of
                            Just cdn ->
                                conductorHost == cdn.frontendHost || conductorHost == cdn.backendHost

                            Nothing ->
                                False
                       )
        in
        if isThisInstance then
            span [ class "server-details-feature-settings-value" ] [ text conductorHost ]

        else
            a
                [ class "server-details-feature-settings-value"
                , href ("https://" ++ conductorHost ++ "/about?tab=cluster")
                , target "_blank"
                ]
                [ text conductorHost ]


heldLocksView : SharedTime.Model -> Bool -> Maybe FreeingLock -> List ClusterResourceLock -> Html Msg
heldLocksView time canEdit freeingLock locks =
    case locks of
        [] ->
            span [ class "server-details-feature-settings-value" ] [ text "None" ]

        _ ->
            div [] (List.map (lockView time canEdit freeingLock) locks)


lockView : SharedTime.Model -> Bool -> Maybe FreeingLock -> ClusterResourceLock -> Html Msg
lockView time canEdit freeingLock lock =
    let
        acquiredText : String
        acquiredText =
            lock.acquiredAt
                |> Maybe.map (timestampToPosix >> SharedTime.formatMoment time)
                |> Maybe.withDefault "unknown time"
    in
    div [ class "server-details-feature-settings-value" ]
        (text (lock.lockHolderNamespaceId ++ ": " ++ acquiredText ++ " ")
            :: (if canEdit then
                    List.map (freeButton freeingLock lock.lockHolderNamespaceId) lock.resources

                else
                    []
               )
        )


{-| "Free <resource name> held by <namespaceId>" -- one per `ClusterResource` in a `lockView`'s
own `lock.resources` (today, that's always exactly one -- `CLUSTER_RESOURCE_BROWSER` is still the
only `ClusterResource` that exists -- but this generalizes to more without changes here). Disabled
while _any_ free is in flight (`freeingLock /= Nothing`), not just this one, since
`FreeClusterResources` only takes one `namespaceId` at a time server-side -- see
`ClusterTab.freeClusterResource`.
-}
freeButton : Maybe FreeingLock -> String -> ClusterResource -> Html Msg
freeButton freeingLock namespaceId resource =
    let
        isFreeing : Bool
        isFreeing =
            freeingLock == Just { namespaceId = namespaceId, resource = resource }
    in
    button
        [ class "server-details-rename-button"
        , onClick (FreeLockClicked namespaceId resource)
        , disabled (freeingLock /= Nothing)
        ]
        [ text
            (if isFreeing then
                "Freeing…"

             else
                "Free " ++ clusterResourceName resource ++ " held by " ++ namespaceId
            )
        ]


clusterResourceName : ClusterResource -> String
clusterResourceName resource =
    case resource of
        CLUSTERRESOURCEBROWSER ->
            "Browser"

        CLUSTERRESOURCEFFMPEG ->
            "FFMPEG"

        CLUSTERRESOURCEIMAGEMAGICK ->
            "ImageMagick"

        ClusterResourceUnrecognized_ _ ->
            "Unknown Resource"


{-| `namespaceId`/`conductorHost`/`sharedSecret` are only `disabled False` (editable) while
`edit.enabled` is on -- turning the main toggle off is the "null the whole config out" action, so
there's nothing useful to type into them until it's back on.
-}
clusterEditView : ClusterConfigEdit -> List (Html Msg)
clusterEditView edit =
    [ Common.settingsRow "Cluster Resource Sharing" (Common.flagSwitch edit.enabled ClusterEnabledToggled)
    , Common.settingsRow "Namespace ID"
        (input
            [ class "server-details-rename-input"
            , placeholder "e.g. its Kubernetes namespace"
            , value edit.namespaceId
            , onInput ClusterNamespaceIdChanged
            , disabled (not edit.enabled || edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Conductor Host"
        (input
            [ class "server-details-rename-input"
            , placeholder "jonline.io"
            , value edit.conductorHost
            , onInput ClusterConductorHostChanged
            , disabled (not edit.enabled || edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Shared Secret"
        (input
            [ class "server-details-rename-input"
            , placeholder "leave blank to keep the current secret"
            , value edit.sharedSecret
            , onInput ClusterSharedSecretChanged
            , disabled (not edit.enabled || edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton ClusterSaveClicked edit.status
        , Common.editCancelButton ClusterCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


{-| Editor for `ClusterConductorState.limits` -- a separate Edit/Save/Cancel from
`clusterEditView` above, reachable (and meaningful) independently of whether cluster resource
sharing itself is even enabled.
-}
limitsEditView : LimitsEdit -> List (Html Msg)
limitsEditView edit =
    [ Common.settingsRow "Browser Instance Limit" (limitInput edit.browser LimitsBrowserChanged edit.status)
    , Common.settingsRow "FFMPEG Process Limit" (limitInput edit.ffmpeg LimitsFfmpegChanged edit.status)
    , Common.settingsRow "ImageMagick Process Limit" (limitInput edit.imagemagick LimitsImagemagickChanged edit.status)
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton LimitsSaveClicked edit.status
        , Common.editCancelButton LimitsCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


{-| A single 0-10 concurrency limit field -- the `min`/`max` attributes are only an HTML/spinner
affordance (a browser still lets someone type outside that range), so the actual clamp happens in
`clampedLimit` via whichever `onChange` message (`LimitsBrowserChanged`/etc.) this is wired to.
Clearing the field entirely doesn't get stuck empty: `clampedLimit` falls back to the field's
current value on an unparseable (e.g. momentarily empty) string, and the very next keystroke
re-syncs the displayed value once it parses again.
-}
limitInput : Int -> (String -> Msg) -> AccountsPanel.FormStatus -> Html Msg
limitInput current onChange status =
    input
        [ type_ "number"
        , Html.Attributes.min "0"
        , Html.Attributes.max "10"
        , class "server-details-rename-input"
        , value (String.fromInt current)
        , onInput onChange
        , disabled (status == AccountsPanel.Submitting)
        ]
        []
