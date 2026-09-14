module Components.Pages.ServerInformationPage.FederationTab exposing (Model, Msg, init, subscriptions, update, view)

{-| The Federation tab of `Components.Pages.ServerInformationPage` -- the server's federated-server
chip strip (add/remove/reorder-animated via `UI.Flip`, see `FederationEdit`'s own doc), the Facebook
App ID/Secret an admin connects so users can create Facebook/Instagram Sync Destinations for their
Posts and Occasions (see `logic::facebook_sync` on the backend), and the Web Push VAPID
public/private keys an admin sets so
`RegisterPushSubscription`'d browsers actually receive notifications (see `backend/src/web_push`).
All three are backed by fields on the same `ServerConfiguration`
(`federationInfo`/`federationInfo.facebookAuthConfig`/`webPushConfig`), saved through the same
`AccountsPanel.updateServerConfig` "fetch fresh copy, then write" dance every other editor on this
page uses.
-}

import Animation
import Browser.Dom as Dom
import Components.Pages.ServerInformationPage.Common as Common
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, img, input, p, span, text)
import Html.Attributes exposing (alt, class, disabled, id, placeholder, src, title, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Html.Keyed
import Http
import Json.Decode as Decode
import Proto.Rellm exposing (FederatedServer, MastodonServer, ServerConfiguration)
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.MastodonServers as MastodonServers exposing (MastodonInstanceInfo)
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import Time
import UI.Classes exposing (classes, hostnameToCSSClass)
import UI.Flip



-- MODEL


type alias Model =
    { federationEdit : Maybe FederationEdit
    , mastodonServersEdit : Maybe MastodonServersEdit
    , facebookAppIdEdit : Maybe TextFieldEdit
    , facebookAppSecretEdit : Maybe TextFieldEdit
    , xTwitterClientIdEdit : Maybe TextFieldEdit
    , xTwitterClientSecretEdit : Maybe TextFieldEdit
    , webPushPublicKeyEdit : Maybe TextFieldEdit
    , webPushPrivateKeyEdit : Maybe TextFieldEdit

    -- A preview image (`MastodonInstanceInfo.logoUrl`, from `GET /api/v1/instance`)
    -- for each `MastodonServer.domain` this tab has ever shown, whether saved
    -- (`mastodonServersDisplayView`) or still mid-edit (`mastodonServersEditorView`) -- see
    -- `ensureMastodonServerLogosFetching`, which populates this reactively (no logo entry at all
    -- means either not yet fetched or fetched-but-none-found; `mastodonServerLogoFetchesStarted`
    -- is what actually distinguishes "not yet fetched" from "tried"). Domains are never removed from
    -- either dict/set once added -- stale entries for a since-removed server are harmless, and
    -- refetching if the same domain is ever re-added would just be wasted work.
    , mastodonServerLogos : Dict String String

    -- Every `MastodonServer.domain` `ensureMastodonServerLogosFetching` has ever kicked off a fetch
    -- for, whether or not it resolved to a real logo -- prevents that function (called on every
    -- single `update`, reactively, since there's no one dedicated "config just loaded" event to
    -- hook instead) from re-firing the same request over and over while a result is still in
    -- flight, or after it resolved with no logo at all (which `mastodonServerLogos` alone can't
    -- distinguish from "haven't tried yet").
    , mastodonServerLogoFetchesStarted : Set String

    -- `True` once `ensureMastodonServerLogosFetching` has run at least once with a resolved
    -- `RellmServer` in hand (i.e. `maybeServer /= Nothing`) -- gates `subscriptions`'
    -- own short-lived poll (`MastodonServerConfigPollTick`), which exists only because nothing else
    -- ever calls into this tab's `update` at all on a fresh page load until the user does something
    -- Federation-tab-specific (clicking the tab itself is handled one level up, in
    -- `ServerInformationPage`, and doesn't route through here) -- without it, `mastodonServerLogos`
    -- would only ever get populated once `MastodonServersEditClicked` (or similar) fires the very
    -- first `Msg` this module ever sees. Once `True`, the poll stops -- by then `maybeServer` has
    -- been seen, so the ordinary per-Msg reactivity `ensureMastodonServerLogosFetching` already
    -- provides is enough to catch any later change (e.g. a server that reconnects after starting
    -- out disconnected).
    , mastodonServerConfigSeen : Bool
    }


type Msg
    = FederationEditClicked
    | FederationCancelClicked
    | FederationSaveClicked
    | GotFederationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | FederatedServerHostInputChanged String
    | FederatedServerAddClicked
    | GotFederatedServerAddResult String (Result Grpc.Error RellmServer)
    | FederatedServerRemoveClicked String
    | FederatedServerRemoved String
    | FederatedServerConfiguredByDefaultToggled String
    | FederatedServerPinnedByDefaultToggled String
    | MoveFederatedServerLeftClicked String
    | MoveFederatedServerRightClicked String
    | GotPreMoveFederatedServerPositions String String Int (Result Dom.Error ( Dom.Element, Dom.Element ))
    | FederatedServerMoveSettled String
    | AnimateFederatedServerFlip Animation.Msg
    | AnimateFederatedServerMove Animation.Msg
    | MastodonServersEditClicked
    | MastodonServersCancelClicked
    | MastodonServersSaveClicked
    | GotMastodonServersSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | MastodonServerDomainInputChanged String
    | MastodonServerAddClicked
    | MastodonServerRemoveClicked String
    | MastodonServerRemoved String
    | MastodonServerConfiguredByDefaultToggled String
    | MastodonServerPinnedByDefaultToggled String
    | MoveMastodonServerLeftClicked String
    | MoveMastodonServerRightClicked String
    | GotPreMoveMastodonServerPositions String String Int (Result Dom.Error ( Dom.Element, Dom.Element ))
    | MastodonServerMoveSettled String
    | AnimateMastodonServerFlip Animation.Msg
    | AnimateMastodonServerMove Animation.Msg
    | MastodonAppIdChanged String String
    | MastodonAppSecretEditClicked String
    | MastodonAppSecretChanged String String
    | MastodonAppSecretCancelClicked String
      -- See `Model.mastodonServerLogos`/`ensureMastodonServerLogosFetching`.
    | GotMastodonServerLogoResult String (Result Http.Error MastodonInstanceInfo)
      -- See `Model.mastodonServerConfigSeen`'s own doc -- a no-op in `updateMsg` itself, purely to
      -- give `update`'s `ensureMastodonServerLogosFetching` wrapper a reason to run again soon
      -- after a fresh page load.
    | MastodonServerConfigPollTick
    | FacebookAppIdEditClicked
    | FacebookAppIdChanged String
    | FacebookAppIdCancelClicked
    | FacebookAppIdSaveClicked
    | GotFacebookAppIdSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | FacebookAppSecretEditClicked
    | FacebookAppSecretChanged String
    | FacebookAppSecretCancelClicked
    | FacebookAppSecretSaveClicked
    | GotFacebookAppSecretSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | XTwitterClientIdEditClicked
    | XTwitterClientIdChanged String
    | XTwitterClientIdCancelClicked
    | XTwitterClientIdSaveClicked
    | GotXTwitterClientIdSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | XTwitterClientSecretEditClicked
    | XTwitterClientSecretChanged String
    | XTwitterClientSecretCancelClicked
    | XTwitterClientSecretSaveClicked
    | GotXTwitterClientSecretSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | WebPushPublicKeyEditClicked
    | WebPushPublicKeyChanged String
    | WebPushPublicKeyCancelClicked
    | WebPushPublicKeySaveClicked
    | GotWebPushPublicKeySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | WebPushPrivateKeyEditClicked
    | WebPushPrivateKeyChanged String
    | WebPushPrivateKeyCancelClicked
    | WebPushPrivateKeySaveClicked
    | GotWebPushPrivateKeySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


{-| Live only while the Federation tab's `FederatedServer` list is being edited by an admin --
`pending` is the in-progress ordered list (its order is this editor's own, never rederived from a
fetch -- see `UI.Flip.remove`'s own doc on why a removing-but-not-yet-removed entry has to keep its
slot rather than being relocated), independent of the actual saved list until `FederationSaveClicked`
succeeds. `hostInput`/`addStatus` back the "type a host, validate it, add it" row
(`FederatedServerAddClicked`, validated via `RellmServers.connectToRellmServer` the same way this page's
own probe validates an unknown server); a freshly-added entry always starts with both flags off (see
`GotFederatedServerAddResult`). `itemAnimations`/`moveAnimations` are this editor's own `UI.Flip`
state for the chip strip's add/remove fade and left/right reorder-slide -- mirrors
`Shared.AccountsPanel`'s `serverAnimations`/`serverMoveAnimations` for its Servers strip, just scoped
to this one in-progress edit instead of the app-wide server list.
-}
type alias FederationEdit =
    { pending : List FederatedServer
    , hostInput : String
    , addStatus : AccountsPanel.FormStatus
    , status : AccountsPanel.FormStatus
    , itemAnimations : Dict String (UI.Flip.State Msg)
    , moveAnimations : Dict String (UI.Flip.MoveState Msg)
    }


{-| Live only while the Federation tab's `MastodonServer` list is being edited by an admin --
mirrors `FederationEdit` exactly (`pending`/`domainInput`/`status`/`itemAnimations`/`moveAnimations`
all play the same role, just keyed by `domain` instead of `host`), except each `pending` entry is a
`MastodonServerEdit` rather than a bare `MastodonServer` (see that type's own doc), and there's no
`addStatus`: unlike `FederatedServerAddClicked`, adding an instance here never round-trips to a
server (there's no live Rellm server to probe -- see `MastodonServerAddClicked`), so it's always
synchronous.
-}
type alias MastodonServersEdit =
    { pending : List MastodonServerEdit
    , domainInput : String
    , status : AccountsPanel.FormStatus
    , itemAnimations : Dict String (UI.Flip.State Msg)
    , moveAnimations : Dict String (UI.Flip.MoveState Msg)
    }


{-| One in-progress `MastodonServer` edit -- `server.appSecret` is always blank here (the server
never sends the real secret back, same as `FacebookAuthConfig.appSecret`/`TextFieldEdit`'s own doc),
and is only overwritten on save if `pendingAppSecret` is non-blank (see `toSavedMastodonServer`) --
the same "blank means leave it alone" convention as every other write-only field on this page, just
tracked per-instance here instead of app-wide. `appSecretEditing` gates whether that field's `<input>`
is shown at all, mirroring the singleton `facebookAppSecretRow`'s Edit-button gating -- starts `True`
for a freshly-added entry (`MastodonServerAddClicked`), since there's no existing secret to hide yet.
-}
type alias MastodonServerEdit =
    { server : MastodonServer
    , pendingAppSecret : String
    , appSecretEditing : Bool
    }


{-| Live only while one of this tab's simple "Edit" -> text field -> Save rows (Facebook App
ID/Secret, see `facebookAuthConfigSection`; Web Push public/private VAPID key, see
`webPushConfigSection`) is being edited by an admin -- `pending` is the in-progress `<input>` value.
The two write-only fields (`FacebookAuthConfig.appSecret`, `WebPushConfig.privateVapidKey`) always
start this at `""` (never pre-filled), since neither is ever actually sent back by the server (see
`ToProtoServerConfiguration` on the backend) -- saving with `pending == ""` is a deliberate no-op
there (leaves whatever's already stored alone), same as leaving a "change password" field blank. The
other two (`appId`, `publicVapidKey`) aren't secret, so their own edits start pre-filled with the
current value instead.
-}
type alias TextFieldEdit =
    { pending : String
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { federationEdit = Nothing
    , mastodonServersEdit = Nothing
    , facebookAppIdEdit = Nothing
    , facebookAppSecretEdit = Nothing
    , xTwitterClientIdEdit = Nothing
    , xTwitterClientSecretEdit = Nothing
    , webPushPublicKeyEdit = Nothing
    , webPushPrivateKeyEdit = Nothing
    , mastodonServerLogos = Dict.empty
    , mastodonServerLogoFetchesStarted = Set.empty
    , mastodonServerConfigSeen = False
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ case model.federationEdit of
            Just edit ->
                Sub.batch
                    [ UI.Flip.subscription AnimateFederatedServerFlip (Dict.values edit.itemAnimations)
                    , UI.Flip.moveSubscription AnimateFederatedServerMove (Dict.values edit.moveAnimations)
                    ]

            Nothing ->
                Sub.none
        , case model.mastodonServersEdit of
            Just edit ->
                Sub.batch
                    [ UI.Flip.subscription AnimateMastodonServerFlip (Dict.values edit.itemAnimations)
                    , UI.Flip.moveSubscription AnimateMastodonServerMove (Dict.values edit.moveAnimations)
                    ]

            Nothing ->
                Sub.none

        -- See `Model.mastodonServerConfigSeen`'s own doc -- a short-lived poll (stops itself once
        -- `maybeServer` has been seen at least once) so `mastodonServerLogos` gets populated on a
        -- fresh page load, not only once the user does something Federation-tab-specific.
        , if model.mastodonServerConfigSeen then
            Sub.none

          else
            Time.every 500 (\_ -> MastodonServerConfigPollTick)
        ]



-- UPDATE


update : Shared.Model -> String -> Bool -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost isSecure maybeServer msg model =
    let
        ( fetchLogosModel, fetchLogosEffect ) =
            ensureMastodonServerLogosFetching maybeServer model

        ( updatedModel, effect ) =
            updateMsg shared targetHost isSecure maybeServer msg fetchLogosModel
    in
    ( updatedModel, Effect.batch [ fetchLogosEffect, effect ] )


{-| Kicks off `MastodonServers.fetchMastodonInstanceInfoTask` for every `MastodonServer.domain`
currently visible anywhere in this tab -- both saved (`maybeServer`'s own `federationInfo`) and
still mid-edit (`model.mastodonServersEdit.pending`, so a domain typed into `MastodonServerAddClicked`
gets a preview before it's ever saved) -- that hasn't been tried yet (see
`Model.mastodonServerLogoFetchesStarted`). Run unconditionally at the top of every `update` call (see
that function): there's no single "the config/edit list just changed" event to hook this to instead,
and the `Set` guard makes that safe -- each domain is only ever fetched once, no matter how many
times this runs.
-}
ensureMastodonServerLogosFetching : Maybe RellmServer -> Model -> ( Model, Effect Msg )
ensureMastodonServerLogosFetching maybeServer model0 =
    let
        -- See `Model.mastodonServerConfigSeen`'s own doc -- stops `subscriptions`' poll once we've
        -- ever had a real `server` to look at, whether or not it actually had any Mastodon servers
        -- configured.
        model : Model
        model =
            case maybeServer of
                Just _ ->
                    { model0 | mastodonServerConfigSeen = True }

                Nothing ->
                    model0

        savedDomains : List String
        savedDomains =
            maybeServer
                |> Maybe.map (RellmServers.configurationOf >> .federationInfo >> Maybe.map .mastodonServers >> Maybe.withDefault [])
                |> Maybe.withDefault []
                |> List.map .domain

        pendingDomains : List String
        pendingDomains =
            model.mastodonServersEdit
                |> Maybe.map (.pending >> List.map (.server >> .domain))
                |> Maybe.withDefault []

        newDomains : List String
        newDomains =
            (savedDomains ++ pendingDomains)
                |> List.filter (\domain -> not (Set.member domain model.mastodonServerLogoFetchesStarted))
                |> Set.fromList
                |> Set.toList
    in
    if List.isEmpty newDomains then
        ( model, Effect.none )

    else
        ( { model | mastodonServerLogoFetchesStarted = List.foldl Set.insert model.mastodonServerLogoFetchesStarted newDomains }
        , newDomains
            |> List.map
                (\domain ->
                    Task.attempt (GotMastodonServerLogoResult domain) (MastodonServers.fetchMastodonInstanceInfoTask domain)
                        |> Effect.fromCmd
                )
            |> Effect.batch
        )


updateMsg : Shared.Model -> String -> Bool -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
updateMsg shared targetHost isSecure maybeServer msg model =
    case msg of
        FederationEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        savedServers : List FederatedServer
                        savedServers =
                            (RellmServers.configurationOf server).federationInfo |> Maybe.map .servers |> Maybe.withDefault []
                    in
                    ( { model
                        | federationEdit =
                            Just
                                { pending = savedServers
                                , hostInput = ""
                                , addStatus = AccountsPanel.Idle
                                , status = AccountsPanel.Idle
                                , itemAnimations = savedServers |> List.map (\federatedServer -> ( federatedServer.host, UI.Flip.restingState )) |> Dict.fromList
                                , moveAnimations = Dict.empty
                                }
                      }
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        FederationCancelClicked ->
            ( { model | federationEdit = Nothing }, Effect.none )

        FederationSaveClicked ->
            case ( model.federationEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | federationEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyFederatedServers edit.pending)
                        |> Task.attempt GotFederationSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFederationSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | federationEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotFederationSaveResult (Err err) ->
            ( { model | federationEdit = model.federationEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        FederatedServerHostInputChanged text ->
            ( { model | federationEdit = model.federationEdit |> Maybe.map (\edit -> { edit | hostInput = text }) }, Effect.none )

        FederatedServerAddClicked ->
            case model.federationEdit of
                Just edit ->
                    let
                        host : String
                        host =
                            String.trim edit.hostInput
                    in
                    if String.isEmpty host || List.any (\federatedServer -> federatedServer.host == host) edit.pending then
                        ( model, Effect.none )

                    else
                        ( { model | federationEdit = Just { edit | addStatus = AccountsPanel.Submitting } }
                        , RellmServers.connectToRellmServer isSecure host
                            |> Task.attempt (GotFederatedServerAddResult host)
                            |> Effect.fromCmd
                        )

                Nothing ->
                    ( model, Effect.none )

        GotFederatedServerAddResult host (Ok _) ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = { host = host, configuredByDefault = Just False, pinnedByDefault = Just False } :: edit.pending
                                    , hostInput = ""
                                    , addStatus = AccountsPanel.Idle
                                    , itemAnimations = Dict.insert host UI.Flip.enter edit.itemAnimations
                                }
                            )
              }
            , Effect.none
            )

        GotFederatedServerAddResult _ (Err err) ->
            ( { model | federationEdit = model.federationEdit |> Maybe.map (\edit -> { edit | addStatus = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        FederatedServerRemoveClicked host ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    currentState : UI.Flip.State Msg
                                    currentState =
                                        Dict.get host edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState
                                in
                                { edit | itemAnimations = Dict.insert host (UI.Flip.remove (FederatedServerRemoved host) currentState) edit.itemAnimations }
                            )
              }
            , Effect.none
            )

        FederatedServerRemoved host ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = List.filter (\federatedServer -> federatedServer.host /= host) edit.pending
                                    , itemAnimations = Dict.remove host edit.itemAnimations
                                }
                            )
              }
            , Effect.none
            )

        FederatedServerConfiguredByDefaultToggled host ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map (mapPendingHost host (\federatedServer -> { federatedServer | configuredByDefault = Just (not (Maybe.withDefault False federatedServer.configuredByDefault)) }))
              }
            , Effect.none
            )

        FederatedServerPinnedByDefaultToggled host ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map (mapPendingHost host (\federatedServer -> { federatedServer | pinnedByDefault = Just (not (Maybe.withDefault False federatedServer.pinnedByDefault)) }))
              }
            , Effect.none
            )

        MoveFederatedServerLeftClicked host ->
            ( model
            , model.federationEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder .host federatedServerChipDomId GotPreMoveFederatedServerPositions -1 host edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        MoveFederatedServerRightClicked host ->
            ( model
            , model.federationEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder .host federatedServerChipDomId GotPreMoveFederatedServerPositions 1 host edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        GotPreMoveFederatedServerPositions host _ offset (Err _) ->
            ( { model
                | federationEdit =
                    model.federationEdit |> Maybe.map (\edit -> { edit | pending = UI.Flip.moveListItemBy .host offset host edit.pending })
              }
            , Effect.none
            )

        GotPreMoveFederatedServerPositions host neighborHost offset (Ok ( chipEl, neighborEl )) ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = UI.Flip.moveListItemBy .host offset host edit.pending
                                    , moveAnimations = UI.Flip.applyReorder UI.Flip.Horizontal FederatedServerMoveSettled host neighborHost chipEl neighborEl edit.moveAnimations
                                }
                            )
              }
            , Effect.none
            )

        FederatedServerMoveSettled host ->
            ( { model
                | federationEdit =
                    model.federationEdit
                        |> Maybe.map (\edit -> { edit | moveAnimations = Dict.update host (Maybe.map (\state -> { state | moving = False })) edit.moveAnimations })
              }
            , Effect.none
            )

        AnimateFederatedServerFlip animMsg ->
            case model.federationEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.animate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.itemAnimations
                    in
                    ( { model | federationEdit = Just { edit | itemAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        AnimateFederatedServerMove animMsg ->
            case model.federationEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.moveAnimate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.moveAnimations
                    in
                    ( { model | federationEdit = Just { edit | moveAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        MastodonServersEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        savedServers : List MastodonServer
                        savedServers =
                            (RellmServers.configurationOf server).federationInfo |> Maybe.map .mastodonServers |> Maybe.withDefault []
                    in
                    ( { model
                        | mastodonServersEdit =
                            Just
                                { pending = savedServers |> List.map (\mastodonServer -> { server = mastodonServer, pendingAppSecret = "", appSecretEditing = False })
                                , domainInput = ""
                                , status = AccountsPanel.Idle
                                , itemAnimations = savedServers |> List.map (\mastodonServer -> ( mastodonServer.domain, UI.Flip.restingState )) |> Dict.fromList
                                , moveAnimations = Dict.empty
                                }
                      }
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        MastodonServersCancelClicked ->
            ( { model | mastodonServersEdit = Nothing }, Effect.none )

        MastodonServersSaveClicked ->
            case ( model.mastodonServersEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | mastodonServersEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyMastodonServers (List.map toSavedMastodonServer edit.pending))
                        |> Task.attempt GotMastodonServersSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotMastodonServersSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | mastodonServersEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotMastodonServersSaveResult (Err err) ->
            ( { model | mastodonServersEdit = model.mastodonServersEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        MastodonServerDomainInputChanged text ->
            ( { model | mastodonServersEdit = model.mastodonServersEdit |> Maybe.map (\edit -> { edit | domainInput = text }) }, Effect.none )

        -- Unlike `FederatedServerAddClicked`, this never round-trips to a server -- a Mastodon
        -- instance isn't a Rellm server, so there's nothing to probe/connect to, and a freshly-typed
        -- domain is just inserted straight into `pending`, synchronously.
        MastodonServerAddClicked ->
            case model.mastodonServersEdit of
                Just edit ->
                    let
                        domain : String
                        domain =
                            String.trim edit.domainInput
                    in
                    if String.isEmpty domain || List.any (\mastodonServerEdit -> mastodonServerEdit.server.domain == domain) edit.pending then
                        ( model, Effect.none )

                    else
                        ( { model
                            | mastodonServersEdit =
                                Just
                                    { edit
                                        | pending =
                                            { server = { domain = domain, appId = "", appSecret = "", configuredByDefault = Just False, pinnedByDefault = Just False }
                                            , pendingAppSecret = ""
                                            , appSecretEditing = True
                                            }
                                                :: edit.pending
                                        , domainInput = ""
                                        , itemAnimations = Dict.insert domain UI.Flip.enter edit.itemAnimations
                                    }
                          }
                        , Effect.none
                        )

                Nothing ->
                    ( model, Effect.none )

        MastodonServerRemoveClicked domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    currentState : UI.Flip.State Msg
                                    currentState =
                                        Dict.get domain edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState
                                in
                                { edit | itemAnimations = Dict.insert domain (UI.Flip.remove (MastodonServerRemoved domain) currentState) edit.itemAnimations }
                            )
              }
            , Effect.none
            )

        MastodonServerRemoved domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = List.filter (\mastodonServerEdit -> mastodonServerEdit.server.domain /= domain) edit.pending
                                    , itemAnimations = Dict.remove domain edit.itemAnimations
                                }
                            )
              }
            , Effect.none
            )

        MastodonServerConfiguredByDefaultToggled domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map (mapPendingMastodonDomain domain (\mastodonServer -> { mastodonServer | configuredByDefault = Just (not (Maybe.withDefault False mastodonServer.configuredByDefault)) }))
              }
            , Effect.none
            )

        MastodonServerPinnedByDefaultToggled domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map (mapPendingMastodonDomain domain (\mastodonServer -> { mastodonServer | pinnedByDefault = Just (not (Maybe.withDefault False mastodonServer.pinnedByDefault)) }))
              }
            , Effect.none
            )

        MoveMastodonServerLeftClicked domain ->
            ( model
            , model.mastodonServersEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder (.server >> .domain) mastodonServerChipDomId GotPreMoveMastodonServerPositions -1 domain edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        MoveMastodonServerRightClicked domain ->
            ( model
            , model.mastodonServersEdit
                |> Maybe.map (\edit -> UI.Flip.beginReorder (.server >> .domain) mastodonServerChipDomId GotPreMoveMastodonServerPositions 1 domain edit.pending)
                |> Maybe.withDefault Cmd.none
                |> Effect.fromCmd
            )

        GotPreMoveMastodonServerPositions domain _ offset (Err _) ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit |> Maybe.map (\edit -> { edit | pending = UI.Flip.moveListItemBy (.server >> .domain) offset domain edit.pending })
              }
            , Effect.none
            )

        GotPreMoveMastodonServerPositions domain neighborDomain offset (Ok ( chipEl, neighborEl )) ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | pending = UI.Flip.moveListItemBy (.server >> .domain) offset domain edit.pending
                                    , moveAnimations = UI.Flip.applyReorder UI.Flip.Horizontal MastodonServerMoveSettled domain neighborDomain chipEl neighborEl edit.moveAnimations
                                }
                            )
              }
            , Effect.none
            )

        MastodonServerMoveSettled domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit
                        |> Maybe.map (\edit -> { edit | moveAnimations = Dict.update domain (Maybe.map (\state -> { state | moving = False })) edit.moveAnimations })
              }
            , Effect.none
            )

        AnimateMastodonServerFlip animMsg ->
            case model.mastodonServersEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.animate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.itemAnimations
                    in
                    ( { model | mastodonServersEdit = Just { edit | itemAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        AnimateMastodonServerMove animMsg ->
            case model.mastodonServersEdit of
                Just edit ->
                    let
                        step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                        step key state ( states, stepCmds ) =
                            let
                                ( newState, cmd ) =
                                    UI.Flip.moveAnimate animMsg state
                            in
                            ( Dict.insert key newState states, cmd :: stepCmds )

                        ( newAnimations, cmds ) =
                            Dict.foldl step ( Dict.empty, [] ) edit.moveAnimations
                    in
                    ( { model | mastodonServersEdit = Just { edit | moveAnimations = newAnimations } }, Effect.fromCmd (Cmd.batch cmds) )

                Nothing ->
                    ( model, Effect.none )

        MastodonAppIdChanged domain text ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit |> Maybe.map (mapPendingMastodonDomain domain (\mastodonServer -> { mastodonServer | appId = text }))
              }
            , Effect.none
            )

        MastodonAppSecretEditClicked domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit |> Maybe.map (mapPendingMastodonEdit domain (\edit -> { edit | appSecretEditing = True }))
              }
            , Effect.none
            )

        MastodonAppSecretChanged domain text ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit |> Maybe.map (mapPendingMastodonEdit domain (\edit -> { edit | pendingAppSecret = text }))
              }
            , Effect.none
            )

        MastodonAppSecretCancelClicked domain ->
            ( { model
                | mastodonServersEdit =
                    model.mastodonServersEdit |> Maybe.map (mapPendingMastodonEdit domain (\edit -> { edit | appSecretEditing = False, pendingAppSecret = "" }))
              }
            , Effect.none
            )

        GotMastodonServerLogoResult domain (Ok info) ->
            ( { model
                | mastodonServerLogos =
                    case info.logoUrl of
                        Just logoUrl ->
                            Dict.insert domain logoUrl model.mastodonServerLogos

                        Nothing ->
                            model.mastodonServerLogos
              }
            , Effect.none
            )

        GotMastodonServerLogoResult _ (Err _) ->
            -- No logo to show -- `mastodonServerLogoImage` already renders nothing at all for a
            -- domain missing from `mastodonServerLogos`, so there's nothing more to do here.
            ( model, Effect.none )

        MastodonServerConfigPollTick ->
            -- All the real work happens in `update`'s own `ensureMastodonServerLogosFetching` call,
            -- which runs before this -- see `Model.mastodonServerConfigSeen`'s own doc.
            ( model, Effect.none )

        FacebookAppIdEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        currentAppId : String
                        currentAppId =
                            (RellmServers.configurationOf server).federationInfo
                                |> Maybe.andThen .facebookAuthConfig
                                |> Maybe.map .appId
                                |> Maybe.withDefault ""
                    in
                    ( { model | facebookAppIdEdit = Just { pending = currentAppId, status = AccountsPanel.Idle } }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        FacebookAppIdChanged text ->
            ( { model | facebookAppIdEdit = model.facebookAppIdEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        FacebookAppIdCancelClicked ->
            ( { model | facebookAppIdEdit = Nothing }, Effect.none )

        FacebookAppIdSaveClicked ->
            case ( model.facebookAppIdEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | facebookAppIdEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyFacebookAppId edit.pending)
                        |> Task.attempt GotFacebookAppIdSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFacebookAppIdSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | facebookAppIdEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotFacebookAppIdSaveResult (Err err) ->
            ( { model | facebookAppIdEdit = model.facebookAppIdEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        FacebookAppSecretEditClicked ->
            ( { model | facebookAppSecretEdit = Just { pending = "", status = AccountsPanel.Idle } }, Effect.none )

        FacebookAppSecretChanged text ->
            ( { model | facebookAppSecretEdit = model.facebookAppSecretEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        FacebookAppSecretCancelClicked ->
            ( { model | facebookAppSecretEdit = Nothing }, Effect.none )

        FacebookAppSecretSaveClicked ->
            case ( model.facebookAppSecretEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | facebookAppSecretEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyFacebookAppSecret edit.pending)
                        |> Task.attempt GotFacebookAppSecretSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFacebookAppSecretSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | facebookAppSecretEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotFacebookAppSecretSaveResult (Err err) ->
            ( { model | facebookAppSecretEdit = model.facebookAppSecretEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        XTwitterClientIdEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        currentClientId : String
                        currentClientId =
                            (RellmServers.configurationOf server).federationInfo
                                |> Maybe.andThen .xTwitterAuthConfig
                                |> Maybe.map .clientId
                                |> Maybe.withDefault ""
                    in
                    ( { model | xTwitterClientIdEdit = Just { pending = currentClientId, status = AccountsPanel.Idle } }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        XTwitterClientIdChanged text ->
            ( { model | xTwitterClientIdEdit = model.xTwitterClientIdEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        XTwitterClientIdCancelClicked ->
            ( { model | xTwitterClientIdEdit = Nothing }, Effect.none )

        XTwitterClientIdSaveClicked ->
            case ( model.xTwitterClientIdEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | xTwitterClientIdEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyXTwitterClientId edit.pending)
                        |> Task.attempt GotXTwitterClientIdSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotXTwitterClientIdSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | xTwitterClientIdEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotXTwitterClientIdSaveResult (Err err) ->
            ( { model | xTwitterClientIdEdit = model.xTwitterClientIdEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        XTwitterClientSecretEditClicked ->
            ( { model | xTwitterClientSecretEdit = Just { pending = "", status = AccountsPanel.Idle } }, Effect.none )

        XTwitterClientSecretChanged text ->
            ( { model | xTwitterClientSecretEdit = model.xTwitterClientSecretEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        XTwitterClientSecretCancelClicked ->
            ( { model | xTwitterClientSecretEdit = Nothing }, Effect.none )

        XTwitterClientSecretSaveClicked ->
            case ( model.xTwitterClientSecretEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | xTwitterClientSecretEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyXTwitterClientSecret edit.pending)
                        |> Task.attempt GotXTwitterClientSecretSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotXTwitterClientSecretSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | xTwitterClientSecretEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotXTwitterClientSecretSaveResult (Err err) ->
            ( { model | xTwitterClientSecretEdit = model.xTwitterClientSecretEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        WebPushPublicKeyEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        currentPublicKey : String
                        currentPublicKey =
                            (RellmServers.configurationOf server).webPushConfig
                                |> Maybe.map .publicVapidKey
                                |> Maybe.withDefault ""
                    in
                    ( { model | webPushPublicKeyEdit = Just { pending = currentPublicKey, status = AccountsPanel.Idle } }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        WebPushPublicKeyChanged text ->
            ( { model | webPushPublicKeyEdit = model.webPushPublicKeyEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        WebPushPublicKeyCancelClicked ->
            ( { model | webPushPublicKeyEdit = Nothing }, Effect.none )

        WebPushPublicKeySaveClicked ->
            case ( model.webPushPublicKeyEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | webPushPublicKeyEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyWebPushPublicKey edit.pending)
                        |> Task.attempt GotWebPushPublicKeySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotWebPushPublicKeySaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | webPushPublicKeyEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotWebPushPublicKeySaveResult (Err err) ->
            ( { model | webPushPublicKeyEdit = model.webPushPublicKeyEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        WebPushPrivateKeyEditClicked ->
            ( { model | webPushPrivateKeyEdit = Just { pending = "", status = AccountsPanel.Idle } }, Effect.none )

        WebPushPrivateKeyChanged text ->
            ( { model | webPushPrivateKeyEdit = model.webPushPrivateKeyEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        WebPushPrivateKeyCancelClicked ->
            ( { model | webPushPrivateKeyEdit = Nothing }, Effect.none )

        WebPushPrivateKeySaveClicked ->
            case ( model.webPushPrivateKeyEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | webPushPrivateKeyEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyWebPushPrivateKey edit.pending)
                        |> Task.attempt GotWebPushPrivateKeySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotWebPushPrivateKeySaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | webPushPrivateKeyEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotWebPushPrivateKeySaveResult (Err err) ->
            ( { model | webPushPrivateKeyEdit = model.webPushPrivateKeyEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )


{-| `FederationSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way
every other editor's transform is -- overlays `servers` (the edit's `pending` list, in its edit's
own order) onto a freshly re-fetched `ServerConfiguration`'s `federationInfo`, leaving
`facebookAuthConfig`/`xTwitterAuthConfig`/`mastodonServers` (and every other field) untouched.
-}
applyFederatedServers : List FederatedServer -> ServerConfiguration -> ServerConfiguration
applyFederatedServers servers config =
    { config
        | federationInfo =
            Just
                { servers = servers
                , facebookAuthConfig = config.federationInfo |> Maybe.andThen .facebookAuthConfig
                , xTwitterAuthConfig = config.federationInfo |> Maybe.andThen .xTwitterAuthConfig
                , mastodonServers = config.federationInfo |> Maybe.map .mastodonServers |> Maybe.withDefault []
                }
    }


{-| `MastodonServersSaveClicked`'s transform -- mirrors `applyFederatedServers` exactly, just
against `federationInfo.mastodonServers` instead of `.servers`, leaving every other field (including
`servers` itself) untouched.
-}
applyMastodonServers : List MastodonServer -> ServerConfiguration -> ServerConfiguration
applyMastodonServers mastodonServers config =
    { config
        | federationInfo =
            Just
                { servers = config.federationInfo |> Maybe.map .servers |> Maybe.withDefault []
                , facebookAuthConfig = config.federationInfo |> Maybe.andThen .facebookAuthConfig
                , xTwitterAuthConfig = config.federationInfo |> Maybe.andThen .xTwitterAuthConfig
                , mastodonServers = mastodonServers
                }
    }


{-| `MastodonServersSaveClicked`'s per-item projection from a `MastodonServerEdit` to the plain
`MastodonServer` the RPC actually sends -- overlays `pendingAppSecret` onto `appSecret` (blank if
never touched, same "leave it alone" meaning `applyFacebookAppSecret`'s blank does), ignoring
`appSecretEditing` (whether the field happened to be visible doesn't matter, only what's in it).
-}
toSavedMastodonServer : MastodonServerEdit -> MastodonServer
toSavedMastodonServer mastodonServerEdit =
    let
        server : MastodonServer
        server =
            mastodonServerEdit.server
    in
    { server | appSecret = mastodonServerEdit.pendingAppSecret }


{-| `FacebookAppIdSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same
way `applyFederatedServers`'s result is -- overlays a new `appId` onto a freshly re-fetched
`ServerConfiguration`'s `federationInfo.facebookAuthConfig`, leaving `servers` untouched. `appSecret`
is always sent blank here: the backend's `ConfigureServer` treats a blank incoming `appSecret` as
"leave whatever's already stored alone" (it's write-only -- see `TextFieldEdit`'s own doc),
so this can never accidentally clobber it.
-}
applyFacebookAppId : String -> ServerConfiguration -> ServerConfiguration
applyFacebookAppId appId config =
    let
        federationInfo : Proto.Rellm.FederationInfo
        federationInfo =
            Maybe.withDefault { servers = [], facebookAuthConfig = Nothing, xTwitterAuthConfig = Nothing, mastodonServers = [] } config.federationInfo
    in
    { config
        | federationInfo =
            Just { federationInfo | facebookAuthConfig = Just { appId = appId, appSecret = "" } }
    }


{-| `FacebookAppSecretSaveClicked`'s transform -- mirrors `applyFacebookAppId`, just overlaying a
new `appSecret` (this time actually non-blank, since this _is_ the save that's meant to change it)
instead. Keeps whatever `appId` the freshly re-fetched config already has.
-}
applyFacebookAppSecret : String -> ServerConfiguration -> ServerConfiguration
applyFacebookAppSecret appSecret config =
    let
        federationInfo : Proto.Rellm.FederationInfo
        federationInfo =
            Maybe.withDefault { servers = [], facebookAuthConfig = Nothing, xTwitterAuthConfig = Nothing, mastodonServers = [] } config.federationInfo

        existingAppId : String
        existingAppId =
            federationInfo.facebookAuthConfig |> Maybe.map .appId |> Maybe.withDefault ""
    in
    { config
        | federationInfo =
            Just { federationInfo | facebookAuthConfig = Just { appId = existingAppId, appSecret = appSecret } }
    }


{-| `XTwitterClientIdSaveClicked`'s transform -- mirrors `applyFacebookAppId` exactly, just against
`federationInfo.xTwitterAuthConfig` instead. `clientSecret` is always sent blank here for the same
"leave whatever's already stored alone" reason.
-}
applyXTwitterClientId : String -> ServerConfiguration -> ServerConfiguration
applyXTwitterClientId clientId config =
    let
        federationInfo : Proto.Rellm.FederationInfo
        federationInfo =
            Maybe.withDefault { servers = [], facebookAuthConfig = Nothing, xTwitterAuthConfig = Nothing, mastodonServers = [] } config.federationInfo
    in
    { config
        | federationInfo =
            Just { federationInfo | xTwitterAuthConfig = Just { clientId = clientId, clientSecret = "" } }
    }


{-| `XTwitterClientSecretSaveClicked`'s transform -- mirrors `applyFacebookAppSecret` exactly, just
against `federationInfo.xTwitterAuthConfig` instead.
-}
applyXTwitterClientSecret : String -> ServerConfiguration -> ServerConfiguration
applyXTwitterClientSecret clientSecret config =
    let
        federationInfo : Proto.Rellm.FederationInfo
        federationInfo =
            Maybe.withDefault { servers = [], facebookAuthConfig = Nothing, xTwitterAuthConfig = Nothing, mastodonServers = [] } config.federationInfo

        existingClientId : String
        existingClientId =
            federationInfo.xTwitterAuthConfig |> Maybe.map .clientId |> Maybe.withDefault ""
    in
    { config
        | federationInfo =
            Just { federationInfo | xTwitterAuthConfig = Just { clientId = existingClientId, clientSecret = clientSecret } }
    }


{-| `WebPushPublicKeySaveClicked`'s transform -- overlays a new `publicVapidKey` onto a freshly
re-fetched `ServerConfiguration`'s `webPushConfig`. `privateVapidKey` is always sent blank here:
same "blank means leave it alone" merge `applyFacebookAppId`'s own `appSecret` relies on, this time
in `ConfigureServer`'s `WebPushConfig`-specific merge block (see that RPC's own doc comment).
-}
applyWebPushPublicKey : String -> ServerConfiguration -> ServerConfiguration
applyWebPushPublicKey publicKey config =
    { config | webPushConfig = Just { publicVapidKey = publicKey, privateVapidKey = "" } }


{-| `WebPushPrivateKeySaveClicked`'s transform -- mirrors `applyWebPushPublicKey`, just overlaying a
new `privateVapidKey` (this time actually non-blank, since this _is_ the save that's meant to change
it) instead. Keeps whatever `publicVapidKey` the freshly re-fetched config already has.
-}
applyWebPushPrivateKey : String -> ServerConfiguration -> ServerConfiguration
applyWebPushPrivateKey privateKey config =
    let
        existingPublicKey : String
        existingPublicKey =
            config.webPushConfig |> Maybe.map .publicVapidKey |> Maybe.withDefault ""
    in
    { config | webPushConfig = Just { publicVapidKey = existingPublicKey, privateVapidKey = privateKey } }


{-| Updates the one entry of `edit.pending` matching `host`, if any --
`FederatedServerConfiguredByDefaultToggled`/`FederatedServerPinnedByDefaultToggled`'s shared
plumbing.
-}
mapPendingHost : String -> (FederatedServer -> FederatedServer) -> FederationEdit -> FederationEdit
mapPendingHost host fn edit =
    { edit
        | pending =
            edit.pending
                |> List.map
                    (\federatedServer ->
                        if federatedServer.host == host then
                            fn federatedServer

                        else
                            federatedServer
                    )
    }


{-| The DOM `id` a federated-server chip is rendered with while `federationEdit` is active -- the
`UI.Flip.Horizontal` counterpart of `AccountsPanel.feedItemChipDomId`, for
`MoveFederatedServerLeftClicked`/`MoveFederatedServerRightClicked` to measure. Deliberately its own
id scheme (not `AccountsPanel.feedItemChipDomId`) even though a federated host can coincide with an
already-added server's own `frontendHost` -- that server's own chip (in the Accounts Panel, via
`UI.serversStrip`) can be on-screen at the very same time this tab is, and DOM ids must be unique.
-}
federatedServerChipDomId : String -> String
federatedServerChipDomId host =
    "federated-server-chip-" ++ host


{-| Updates the one `pending` entry's `MastodonServer` matching `domain`, if any --
`MastodonServerConfiguredByDefaultToggled`/`MastodonServerPinnedByDefaultToggled`/`MastodonAppIdChanged`'s
shared plumbing, mirroring `mapPendingHost`.
-}
mapPendingMastodonDomain : String -> (MastodonServer -> MastodonServer) -> MastodonServersEdit -> MastodonServersEdit
mapPendingMastodonDomain domain fn edit =
    { edit
        | pending =
            edit.pending
                |> List.map
                    (\mastodonServerEdit ->
                        if mastodonServerEdit.server.domain == domain then
                            { mastodonServerEdit | server = fn mastodonServerEdit.server }

                        else
                            mastodonServerEdit
                    )
    }


{-| Updates the one `pending` entry's `MastodonServerEdit` wrapper matching `domain`, if any --
`MastodonAppSecretEditClicked`/`MastodonAppSecretChanged`/`MastodonAppSecretCancelClicked`'s shared
plumbing (the `appSecretEditing`/`pendingAppSecret` fields live on the wrapper, not the inner
`MastodonServer` -- see `MastodonServerEdit`'s own doc), otherwise identical to `mapPendingMastodonDomain`.
-}
mapPendingMastodonEdit : String -> (MastodonServerEdit -> MastodonServerEdit) -> MastodonServersEdit -> MastodonServersEdit
mapPendingMastodonEdit domain fn edit =
    { edit
        | pending =
            edit.pending
                |> List.map
                    (\mastodonServerEdit ->
                        if mastodonServerEdit.server.domain == domain then
                            fn mastodonServerEdit

                        else
                            mastodonServerEdit
                    )
    }


{-| The DOM `id` a Mastodon-server chip is rendered with while `mastodonServersEdit` is active --
mirrors `federatedServerChipDomId` exactly, just its own id scheme (never collides, but kept
separate on principle the same way that one is from `AccountsPanel.feedItemChipDomId`).
-}
mastodonServerChipDomId : String -> String
mastodonServerChipDomId domain =
    "mastodon-server-chip-" ++ domain


{-| The `RellmServer` to show a federated host's name/logo off of -- the real,
already-known one if `host` happens to also be a known `Server` (e.g. also added to Accounts &
Servers), otherwise a synthetic unconnected record whose `RellmServers.brandingOf` falls back to
the bare host string (no logo, no separate name) -- same "synthesize an unconnected `Server`"
fallback `UI.recommendedServerChip` uses for a host it hasn't background-connected to yet.
-}
federatedServerFor : Shared.Model -> String -> RellmServer
federatedServerFor shared host =
    RellmServers.rellmServerForHost shared.accounts.servers host
        |> Maybe.withDefault { frontendHost = host, enabled = False, connected = Nothing, sortOrder = 0 }



-- VIEW


{-| Only an admin sees the Edit button (and, once clicked, the editor -- see
`federationEditorView`); anyone else just sees the read-only chip strip
(`federationDisplayView`), same split as every other editor on this page.
-}
view : Shared.Model -> RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view shared server maybeAdminAccount model =
    div [ class "server-details-tab-content server-details-federation" ]
        [ h3 [ class "section-title" ] [ text "Federated Servers" ]
        , case model.federationEdit of
            Just edit ->
                federationEditorView shared edit

            Nothing ->
                let
                    savedServers : List FederatedServer
                    savedServers =
                        (RellmServers.configurationOf server).federationInfo |> Maybe.map .servers |> Maybe.withDefault []
                in
                federationDisplayView shared savedServers
        , case ( model.federationEdit, maybeAdminAccount ) of
            ( Nothing, Just _ ) ->
                button [ class "server-details-rename-button", onClick FederationEditClicked ] [ text "Edit Federation" ]

            _ ->
                text ""
        , mastodonServersSection server model maybeAdminAccount
        , facebookAuthConfigSection server model maybeAdminAccount
        , xTwitterAuthConfigSection server model maybeAdminAccount
        , webPushConfigSection server model maybeAdminAccount
        ]


{-| A `FederatedServer`-style chip strip (add/remove/reorder via `UI.Flip`, mirrors
`federationEditorView`/`federatedServerEditChip` exactly), except each chip also edits that
instance's App ID (plain) and App Secret (write-only) inline -- see `MastodonServerEdit`'s own doc
for why the secret needs its own bit of edit-mode state per chip, unlike `FederatedServer`'s two
plain boolean toggles. Unlike `FederatedServer` chips, there's no `RellmServers.rellmServerNameAndLogo`
branding to show -- a Mastodon instance is never also a known Rellm `Server`.
-}
mastodonServersSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
mastodonServersSection server model maybeAdminAccount =
    div [ class "server-details-facebook-auth" ]
        [ h3 [ class "section-title" ] [ text "Mastodon Servers" ]
        , case model.mastodonServersEdit of
            Just edit ->
                mastodonServersEditorView model.mastodonServerLogos edit

            Nothing ->
                let
                    savedServers : List MastodonServer
                    savedServers =
                        (RellmServers.configurationOf server).federationInfo |> Maybe.map .mastodonServers |> Maybe.withDefault []
                in
                mastodonServersDisplayView model.mastodonServerLogos savedServers
        , case ( model.mastodonServersEdit, maybeAdminAccount ) of
            ( Nothing, Just _ ) ->
                button [ class "server-details-rename-button", onClick MastodonServersEditClicked ] [ text "Edit Mastodon Servers" ]

            _ ->
                text ""
        ]


mastodonServersDisplayView : Dict String String -> List MastodonServer -> Html Msg
mastodonServersDisplayView logos mastodonServers =
    if List.isEmpty mastodonServers then
        p [] [ text "No Mastodon instances are configured." ]

    else
        div [ class "federated-servers-strip" ] (List.map (mastodonServerDisplayChip logos) mastodonServers)


{-| One `MastodonServer`, read-only -- mirrors `federatedServerDisplayChip`, just showing whether an
App ID is configured (never the secret) instead of a Rellm server's logo/name. `logos` is
`Model.mastodonServerLogos` -- see `mastodonServerLogoImage`.
-}
mastodonServerDisplayChip : Dict String String -> MastodonServer -> Html Msg
mastodonServerDisplayChip logos mastodonServer =
    let
        configuredByDefault : Bool
        configuredByDefault =
            Maybe.withDefault False mastodonServer.configuredByDefault

        pinnedByDefault : Bool
        pinnedByDefault =
            Maybe.withDefault False mastodonServer.pinnedByDefault
    in
    div [ classes [ "server-chip", "federated-server-chip", hostnameToCSSClass mastodonServer.domain ] ]
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ div [ class "server-chip-host-row" ] [ mastodonServerLogoImage logos mastodonServer.domain ]
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text mastodonServer.domain ] ]
            , let
                appIdLabel: String
                appIdLabel =
                    if String.isEmpty mastodonServer.appId then
                        "App ID not set"

                    else
                        "App ID: " ++ mastodonServer.appId
              in
              div [ class "mastodon-app-id", title appIdLabel ]
                [ text appIdLabel ]
            ]
        , div [ classes [ "server-chip-bottom", "federated-server-flags", "background-color-nav" ] ]
            [ if configuredByDefault then
                span [ class "federated-server-flag-badge" ] [ text "Added by Default" ]

              else
                text ""
            , if pinnedByDefault then
                span [ class "federated-server-flag-badge" ] [ text "Enabled by Default" ]

              else
                text ""
            , if not configuredByDefault && not pinnedByDefault then
                span [ class "federated-server-flag-none" ] [ text "—" ]

              else
                text ""
            ]
        ]


{-| The chip strip, the "type a domain, add it" row, and the Save/Cancel actions -- mirrors
`federationEditorView` exactly, minus the "Checking…" submitting state on Add (see
`MastodonServerAddClicked`'s own doc: there's nothing to check).
-}
mastodonServersEditorView : Dict String String -> MastodonServersEdit -> Html Msg
mastodonServersEditorView logos edit =
    div [ class "server-details-federation-edit" ]
        [ Html.Keyed.node "div"
            [ classes [ "federated-servers-strip", "flip-animated-row" ] ]
            (List.indexedMap
                (\index mastodonServerEdit -> ( mastodonServerEdit.server.domain, mastodonServerEditChipFlip logos edit (List.length edit.pending) index mastodonServerEdit ))
                edit.pending
            )
        , div [ class "server-details-federation-add" ]
            [ input
                [ class "server-details-federation-add-input"
                , value edit.domainInput
                , onInput MastodonServerDomainInputChanged
                , placeholder "mastodon.world"
                ]
                []
            , button
                [ class "server-details-rename-button"
                , onClick MastodonServerAddClicked
                , disabled (String.isEmpty (String.trim edit.domainInput))
                ]
                [ text "Add Instance" ]
            ]
        , div [ class "server-details-permissions-actions" ]
            [ Common.editSaveButton MastodonServersSaveClicked edit.status
            , Common.editCancelButton MastodonServersCancelClicked edit.status
            ]
        , Common.editErrorView edit.status
        ]


{-| Wraps `mastodonServerEditChip` in the same fading/scaling/collapsing outer `div` as
`federatedServerEditChipFlip` -- see that function's own doc.
-}
mastodonServerEditChipFlip : Dict String String -> MastodonServersEdit -> Int -> Int -> MastodonServerEdit -> Html Msg
mastodonServerEditChipFlip logos edit count index mastodonServerEdit =
    let
        domain : String
        domain =
            mastodonServerEdit.server.domain

        flipState : UI.Flip.State Msg
        flipState =
            Dict.get domain edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get domain edit.moveAnimations |> Maybe.map .moving |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ Html.Attributes.style "pointer-events" "none" ]

            else
                []
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flipState isMoving)
        [ div pointerEventsAttr [ mastodonServerEditChip logos edit count index mastodonServerEdit ] ]


{-| One Mastodon instance's editor chip -- mirrors `federatedServerEditChip`'s reorder arrows/domain
header/remove button exactly, plus inline App ID/App Secret fields (see `mastodonAppIdField`/
`mastodonAppSecretField`) in place of `FederatedServer`'s two plain boolean toggles... which this
still also has, since `MastodonServer` carries the same `configuredByDefault`/`pinnedByDefault` pair.
`logos` is `Model.mastodonServerLogos` -- see `mastodonServerLogoImage`.
-}
mastodonServerEditChip : Dict String String -> MastodonServersEdit -> Int -> Int -> MastodonServerEdit -> Html Msg
mastodonServerEditChip logos edit count index mastodonServerEdit =
    let
        mastodonServer : MastodonServer
        mastodonServer =
            mastodonServerEdit.server

        domain : String
        domain =
            mastodonServer.domain

        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            edit.moveAnimations |> Dict.get domain |> Maybe.map UI.Flip.moveAttributes |> Maybe.withDefault []

        stopClick : Msg -> Html.Attribute Msg
        stopClick msg =
            stopPropagationOn "click" (Decode.succeed ( msg, True ))

        showBackward : Bool
        showBackward =
            index > 0

        showForward : Bool
        showForward =
            index < count - 1

        reorderPair : { backward : Html Msg, forward : Html Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Horizontal
                { moveBackward = stopClick (MoveMastodonServerLeftClicked domain)
                , moveForward = stopClick (MoveMastodonServerRightClicked domain)
                , canMoveBackward = showBackward
                , canMoveForward = showForward
                }
    in
    div
        (id (mastodonServerChipDomId domain)
            :: classes [ "server-chip", "federated-server-chip", "federated-server-chip-edit", "mastodon-server-chip-edit", hostnameToCSSClass domain ]
            :: moveAttrs
        )
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ div [ class "server-chip-logo-row" ]
                [ div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showBackward ) ] ] [ reorderPair.backward ]
                , mastodonServerLogoImage logos domain
                , div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showForward ) ] ] [ reorderPair.forward ]
                ]
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text domain ] ]
            ]
        , div [ classes [ "server-chip-bottom", "federated-server-flags-edit", "background-color-nav" ] ]
            [ mastodonAppIdField domain mastodonServer.appId
            , mastodonAppSecretField domain mastodonServerEdit
            , federatedServerFlagToggle "Added by Default" (Maybe.withDefault False mastodonServer.configuredByDefault) (MastodonServerConfiguredByDefaultToggled domain)
            , federatedServerFlagToggle "Enabled by Default" (Maybe.withDefault False mastodonServer.pinnedByDefault) (MastodonServerPinnedByDefaultToggled domain)
            , div [ class "federated-server-chip-remove" ]
                [ button
                    [ class "remove-btn"
                    , onClick (MastodonServerRemoveClicked domain)
                    , title ("Remove " ++ domain)
                    ]
                    [ text "╳" ]
                ]
            ]
        ]


{-| A Mastodon server's preview image (`Model.mastodonServerLogos`, fetched via
`ensureMastodonServerLogosFetching`) -- `text ""` (nothing rendered) until/unless it resolves, same
"no placeholder while loading" convention as `UI.federatedFeedLogoImage`. Reuses that function's own
`.server-logo-image` sizing (32px, un-rounded -- this is a server logo, not a user avatar, so no
`.server-logo-image-circular`).
-}
mastodonServerLogoImage : Dict String String -> String -> Html msg
mastodonServerLogoImage logos domain =
    case Dict.get domain logos of
        Just logoUrl ->
            img [ class "server-logo-image", src logoUrl, alt (domain ++ " logo") ] []

        Nothing ->
            text ""


mastodonAppIdField : String -> String -> Html Msg
mastodonAppIdField domain appId =
    div [ class "server-details-color-row" ]
        [ span [ class "server-details-color-label" ] [ text "App ID" ]
        , input
            [ class "server-details-rename-input"
            , value appId
            , onInput (MastodonAppIdChanged domain)
            ]
            []
        ]


{-| Unlike `mastodonAppIdField`, there's no "current value" to show when not editing -- mirrors
`facebookAppSecretRow`'s own doc exactly, just per-instance (see `MastodonServerEdit.appSecretEditing`).
-}
mastodonAppSecretField : String -> MastodonServerEdit -> Html Msg
mastodonAppSecretField domain mastodonServerEdit =
    if mastodonServerEdit.appSecretEditing then
        div [ class "server-details-color-row server-details-color-row-edit" ]
            [ span [ class "server-details-color-label" ] [ text "App Secret" ]
            , input
                [ Html.Attributes.type_ "password"
                , class "server-details-rename-input"
                , placeholder "New App Secret"
                , value mastodonServerEdit.pendingAppSecret
                , onInput (MastodonAppSecretChanged domain)
                ]
                []
            , button [ class "server-details-rename-button", onClick (MastodonAppSecretCancelClicked domain) ] [ text "Cancel" ]
            ]

    else
        div [ class "server-details-color-row" ]
            [ span [ class "server-details-color-label" ] [ text "App Secret" ]
            , span [ class "server-details-color-hex" ] [ text "Never shown" ]
            , button [ class "server-details-rename-button", onClick (MastodonAppSecretEditClicked domain) ] [ text "Edit" ]
            ]


facebookAuthConfigSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
facebookAuthConfigSection server model maybeAdminAccount =
    let
        currentAppId : String
        currentAppId =
            (RellmServers.configurationOf server).federationInfo
                |> Maybe.andThen .facebookAuthConfig
                |> Maybe.map .appId
                |> Maybe.withDefault ""
    in
    div [ class "server-details-facebook-auth" ]
        (h3 [ class "section-title" ] [ text "Facebook Authentication Configuration" ]
            :: facebookAppIdRow currentAppId model.facebookAppIdEdit maybeAdminAccount
            :: (case maybeAdminAccount of
                    Just _ ->
                        [ facebookAppSecretRow model.facebookAppSecretEdit maybeAdminAccount ]

                    Nothing ->
                        []
               )
        )


facebookAppIdRow : String -> Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
facebookAppIdRow currentAppId maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "App ID" ]
                , input
                    [ class "server-details-rename-input"
                    , value edit.pending
                    , onInput FacebookAppIdChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton FacebookAppIdSaveClicked edit.status
                , Common.editCancelButton FacebookAppIdCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "App ID" ]
                , span [ class "server-details-color-hex" ]
                    [ text
                        (if String.isEmpty currentAppId then
                            "Not set."

                         else
                            currentAppId
                        )
                    ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick FacebookAppIdEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Unlike `facebookAppIdRow`, there's no "current value" to show when not editing -- the server
never sends the real `appSecret` back (see `TextFieldEdit`'s doc), so the placeholder below
is shown regardless of whether a secret is actually configured. Clicking Edit always starts from a
blank `<input>`; saving it blank is a no-op on the backend, same as leaving a "change password"
field untouched.
-}
facebookAppSecretRow : Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
facebookAppSecretRow maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "App Secret" ]
                , input
                    [ Html.Attributes.type_ "password"
                    , class "server-details-rename-input"
                    , placeholder "New App Secret"
                    , value edit.pending
                    , onInput FacebookAppSecretChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton FacebookAppSecretSaveClicked edit.status
                , Common.editCancelButton FacebookAppSecretCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "App Secret" ]
                , span [ class "server-details-color-hex" ] [ text "Never shown" ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick FacebookAppSecretEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Mirrors `facebookAuthConfigSection` exactly, against `federationInfo.xTwitterAuthConfig`
instead -- one admin-registered X Developer App (Client ID + Client Secret), shared by every user's
own connected `XTwitterAccount` (see `protos/sync.proto`'s doc on that message, and
`logic::x_twitter_sync` on the backend).
-}
xTwitterAuthConfigSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
xTwitterAuthConfigSection server model maybeAdminAccount =
    let
        currentClientId : String
        currentClientId =
            (RellmServers.configurationOf server).federationInfo
                |> Maybe.andThen .xTwitterAuthConfig
                |> Maybe.map .clientId
                |> Maybe.withDefault ""
    in
    div [ class "server-details-facebook-auth" ]
        (h3 [ class "section-title" ] [ text "X (Twitter) Authentication Configuration" ]
            :: xTwitterClientIdRow currentClientId model.xTwitterClientIdEdit maybeAdminAccount
            :: (case maybeAdminAccount of
                    Just _ ->
                        [ xTwitterClientSecretRow model.xTwitterClientSecretEdit maybeAdminAccount ]

                    Nothing ->
                        []
               )
        )


xTwitterClientIdRow : String -> Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
xTwitterClientIdRow currentClientId maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Client ID" ]
                , input
                    [ class "server-details-rename-input"
                    , value edit.pending
                    , onInput XTwitterClientIdChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton XTwitterClientIdSaveClicked edit.status
                , Common.editCancelButton XTwitterClientIdCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Client ID" ]
                , span [ class "server-details-color-hex" ]
                    [ text
                        (if String.isEmpty currentClientId then
                            "Not set."

                         else
                            currentClientId
                        )
                    ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick XTwitterClientIdEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Unlike `xTwitterClientIdRow`, there's no "current value" to show when not editing -- mirrors
`facebookAppSecretRow`'s own doc exactly.
-}
xTwitterClientSecretRow : Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
xTwitterClientSecretRow maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Client Secret" ]
                , input
                    [ Html.Attributes.type_ "password"
                    , class "server-details-rename-input"
                    , placeholder "New Client Secret"
                    , value edit.pending
                    , onInput XTwitterClientSecretChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton XTwitterClientSecretSaveClicked edit.status
                , Common.editCancelButton XTwitterClientSecretCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Client Secret" ]
                , span [ class "server-details-color-hex" ] [ text "Never shown" ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick XTwitterClientSecretEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Mirrors `facebookAuthConfigSection`: the read-only Public VAPID key (needed by any browser
calling `pushManager.subscribe`, see `Shared.AccountsPanel`'s "Enable notifications") is shown to
everyone, same as the Facebook section's App ID; the Private VAPID key (needed only to sign
outgoing pushes, see `backend/src/web_push`) is admin-only, same as the App Secret.
-}
webPushConfigSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
webPushConfigSection server model maybeAdminAccount =
    let
        currentPublicKey : String
        currentPublicKey =
            (RellmServers.configurationOf server).webPushConfig
                |> Maybe.map .publicVapidKey
                |> Maybe.withDefault ""
    in
    div [ class "server-details-facebook-auth" ]
        (h3 [ class "section-title" ] [ text "Web Push Configuration" ]
            :: webPushPublicKeyRow currentPublicKey model.webPushPublicKeyEdit maybeAdminAccount
            :: (case maybeAdminAccount of
                    Just _ ->
                        [ webPushPrivateKeyRow model.webPushPrivateKeyEdit maybeAdminAccount ]

                    Nothing ->
                        []
               )
        )


webPushPublicKeyRow : String -> Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
webPushPublicKeyRow currentPublicKey maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Public VAPID Key" ]
                , input
                    [ class "server-details-rename-input"
                    , value edit.pending
                    , onInput WebPushPublicKeyChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton WebPushPublicKeySaveClicked edit.status
                , Common.editCancelButton WebPushPublicKeyCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Public VAPID Key" ]
                , span [ class "server-details-color-hex" ]
                    [ text
                        (if String.isEmpty currentPublicKey then
                            "Not set."

                         else
                            currentPublicKey
                        )
                    ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick WebPushPublicKeyEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Unlike `webPushPublicKeyRow`, there's no "current value" to show when not editing -- the server
never sends the real `privateVapidKey` back (see `TextFieldEdit`'s doc), so the placeholder below is
shown regardless of whether a key is actually configured. Clicking Edit always starts from a blank
`<input>`; saving it blank is a no-op on the backend, same as leaving a "change password" field
untouched.
-}
webPushPrivateKeyRow : Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
webPushPrivateKeyRow maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Private VAPID Key" ]
                , input
                    [ Html.Attributes.type_ "password"
                    , class "server-details-rename-input"
                    , placeholder "New Private VAPID Key"
                    , value edit.pending
                    , onInput WebPushPrivateKeyChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton WebPushPrivateKeySaveClicked edit.status
                , Common.editCancelButton WebPushPrivateKeyCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Private VAPID Key" ]
                , span [ class "server-details-color-hex" ] [ text "Never shown" ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick WebPushPrivateKeyEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


federationDisplayView : Shared.Model -> List FederatedServer -> Html Msg
federationDisplayView shared servers =
    if List.isEmpty servers then
        p [] [ text "This server doesn't federate with any other servers." ]

    else
        div [ class "federated-servers-strip" ] (List.map (federatedServerDisplayChip shared) servers)


{-| One federated server, read-only -- host plus (only when set) its two default-federation flags,
renamed for this UI per the module's own convention (`configuredByDefault`/`pinnedByDefault` are how
`AccountsPanel.recommendedFederatedServers`' auto-connect/auto-pin behavior reads them, see that
function's own doc). Styled as one of `UI.serverChip`'s chips (`.server-chip`, `.servers-strip`'s
horizontal-scroll treatment, `.background-color-primary`/`-nav`) rather than introducing a whole new
chip look.
-}
federatedServerDisplayChip : Shared.Model -> FederatedServer -> Html Msg
federatedServerDisplayChip shared federatedServer =
    let
        configuredByDefault : Bool
        configuredByDefault =
            Maybe.withDefault False federatedServer.configuredByDefault

        pinnedByDefault : Bool
        pinnedByDefault =
            Maybe.withDefault False federatedServer.pinnedByDefault
    in
    div [ classes [ "server-chip", "federated-server-chip", hostnameToCSSClass federatedServer.host ] ]
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ RellmServers.rellmServerNameAndLogo (federatedServerFor shared federatedServer.host) RellmServers.RegularServerLogo
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text federatedServer.host ] ]
            ]
        , div [ classes [ "server-chip-bottom", "federated-server-flags", "background-color-nav" ] ]
            [ if configuredByDefault then
                span [ class "federated-server-flag-badge" ] [ text "Added by Default" ]

              else
                text ""
            , if pinnedByDefault then
                span [ class "federated-server-flag-badge" ] [ text "Enabled by Default" ]

              else
                text ""
            , if not configuredByDefault && not pinnedByDefault then
                span [ class "federated-server-flag-none" ] [ text "—" ]

              else
                text ""
            ]
        ]


{-| The chip strip (add/remove/reorder-animated via `UI.Flip`, see `FederationEdit`'s own doc), the
"type a host, validate it, add it" row, and the Save/Cancel actions -- everything shown once
`FederationEditClicked` has started an edit.
-}
federationEditorView : Shared.Model -> FederationEdit -> Html Msg
federationEditorView shared edit =
    div [ class "server-details-federation-edit" ]
        [ Html.Keyed.node "div"
            [ classes [ "federated-servers-strip", "flip-animated-row" ] ]
            (List.indexedMap
                (\index federatedServer -> ( federatedServer.host, federatedServerEditChipFlip shared edit (List.length edit.pending) index federatedServer ))
                edit.pending
            )
        , div [ class "server-details-federation-add" ]
            [ input
                [ class "server-details-federation-add-input"
                , value edit.hostInput
                , onInput FederatedServerHostInputChanged
                , placeholder "example.com"
                , disabled (edit.addStatus == AccountsPanel.Submitting)
                ]
                []
            , button
                [ class "server-details-rename-button"
                , onClick FederatedServerAddClicked
                , disabled (String.isEmpty (String.trim edit.hostInput) || edit.addStatus == AccountsPanel.Submitting)
                ]
                [ text
                    (if edit.addStatus == AccountsPanel.Submitting then
                        "Checking…"

                     else
                        "Add Server"
                    )
                ]
            , Common.editErrorView edit.addStatus
            ]
        , div [ class "server-details-permissions-actions" ]
            [ Common.editSaveButton FederationSaveClicked edit.status
            , Common.editCancelButton FederationCancelClicked edit.status
            ]
        , Common.editErrorView edit.status
        ]


{-| Wraps `federatedServerEditChip` in a fading/scaling/collapsing animated outer `div` (entering
when freshly added via `FederatedServerAddClicked`, removing when `FederatedServerRemoveClicked`) --
the edit-mode counterpart of `UI.serverChipFlip`, whose doc covers the two-layer reasoning
(fade/collapse here vs. the chip's own, independent reorder-slide) in full.
-}
federatedServerEditChipFlip : Shared.Model -> FederationEdit -> Int -> Int -> FederatedServer -> Html Msg
federatedServerEditChipFlip shared edit count index federatedServer =
    let
        flipState : UI.Flip.State Msg
        flipState =
            Dict.get federatedServer.host edit.itemAnimations |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get federatedServer.host edit.moveAnimations |> Maybe.map .moving |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ Html.Attributes.style "pointer-events" "none" ]

            else
                []
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flipState isMoving)
        [ div pointerEventsAttr [ federatedServerEditChip shared edit count index federatedServer ] ]


{-| One federated server's editor chip: left/right reorder arrows flanking the host (mirrors
`UI.serverChip`'s own, `stopPropagationOn` for the same reason -- see
`UI.Flip.reorderButtonPair`'s doc), the two default-federation flags as toggle switches (always
starting off for a freshly-added server, see `GotFederatedServerAddResult`), and a remove button.
-}
federatedServerEditChip : Shared.Model -> FederationEdit -> Int -> Int -> FederatedServer -> Html Msg
federatedServerEditChip shared edit count index federatedServer =
    let
        host : String
        host =
            federatedServer.host

        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            edit.moveAnimations |> Dict.get host |> Maybe.map UI.Flip.moveAttributes |> Maybe.withDefault []

        stopClick : Msg -> Html.Attribute Msg
        stopClick msg =
            stopPropagationOn "click" (Decode.succeed ( msg, True ))

        showBackward : Bool
        showBackward =
            index > 0

        showForward : Bool
        showForward =
            index < count - 1

        reorderPair : { backward : Html Msg, forward : Html Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Horizontal
                { moveBackward = stopClick (MoveFederatedServerLeftClicked host)
                , moveForward = stopClick (MoveFederatedServerRightClicked host)
                , canMoveBackward = showBackward
                , canMoveForward = showForward
                }
    in
    div
        (id (federatedServerChipDomId host)
            :: classes [ "server-chip", "federated-server-chip", "federated-server-chip-edit", hostnameToCSSClass host ]
            :: moveAttrs
        )
        [ div [ classes [ "server-chip-top", "background-color-primary" ] ]
            [ div [ class "server-chip-logo-row" ]
                [ div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showBackward ) ] ] [ reorderPair.backward ]
                , RellmServers.rellmServerNameAndLogo (federatedServerFor shared host) RellmServers.RegularServerLogo
                , div [ Html.Attributes.classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showForward ) ] ] [ reorderPair.forward ]
                ]
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text host ] ]
            ]
        , div [ classes [ "server-chip-bottom", "federated-server-flags-edit", "background-color-nav" ] ]
            [ federatedServerFlagToggle "Added by Default" (Maybe.withDefault False federatedServer.configuredByDefault) (FederatedServerConfiguredByDefaultToggled host)
            , federatedServerFlagToggle "Enabled by Default" (Maybe.withDefault False federatedServer.pinnedByDefault) (FederatedServerPinnedByDefaultToggled host)
            , div [ class "federated-server-chip-remove" ]
                [ button
                    [ class "remove-btn"
                    , onClick (FederatedServerRemoveClicked host)
                    , title ("Remove " ++ host)
                    ]
                    [ text "╳" ]
                ]
            ]
        ]


federatedServerFlagToggle : String -> Bool -> Msg -> Html Msg
federatedServerFlagToggle label_ isChecked toggleMsg =
    div [ class "federated-server-flag-toggle" ]
        [ span [ class "federated-server-flag-toggle-label" ] [ text label_ ]
        , Common.flagSwitch isChecked toggleMsg
        ]
