module Components.Pages.ServerInformationPage exposing (Model, Msg, fromShared, init, subscriptions, titleFor, update, view)

{-| The shared guts of a read-only Rellm server detail page -- reused by
`Pages.Server.ServerIdentifier_` (`/server/[http|https]:hostname`, an
arbitrary server) and `Pages.About` (always `mainFrontendHost`, shown above
the app's own "About Rellm" blurb). Mirrors `Components.Pages.UserProfilePage`,
generalized the same way over "which server" that module is over "which user."

If the server's already known (added to `Shared.AccountsPanel`, i.e. the user
has it in their Accounts & Servers), its live, cached `Server` is shown.
Otherwise this page probes it itself (`RellmServers.connectToRellmServer`) purely
for display -- that probe is never written back to `Shared.AccountsPanel`
unless the user explicitly clicks "Add Server" (`AddServerClicked`), which
dispatches the same `AccountsPanel.ServerConnected` used by the Accounts
panel's own "Add Server" flow. (For `Pages.About`'s `mainFrontendHost`, this
branch is essentially unreachable -- that server is always already known --
but there's no reason to special-case it out.)

Almost everything shown lives in `Server.configuration` (a `ServerConfiguration`)
-- the sole exception is the About tab's admin list, which needs its own
`GetUsers` fetch (there's no dedicated "list admins" RPC yet, so this fetches
a page of users and filters for `ADMIN` client-side, same as the Tamagui
screen does).

This module is purely an orchestrator -- an admin's actual mutations (renaming,
editing the description/privacy policy/media policy, the Default Web UI, the
Anonymous/Default/Basic User Permissions sets, the five per-feature settings
sections, the server's logo/colors, Federation/Facebook Auth config, and the
CDN config) each live in one of five per-tab submodules
(`ServerInformationPage.AboutTab`/`ThemeTab`/`SettingsTab`/`FederationTab`/
`CdnTab`), composed here the same way `Shared.elm` composes
`Shared.AccountsPanel`/`Shared.MarkdownPanel`: this `Model` holds one field per
submodule's own `Model`, this `Msg` wraps each submodule's own `Msg` in a
constructor, and `updateInner` dispatches a wrapped `Msg` to its submodule via
`Effect.map`/`Tuple.mapFirst`, mirroring `Pages.Server.ServerIdentifier_`'s own
wrapping of this module. `Components.Pages.ServerInformationPage.Common` holds
the handful of `msg`-generic bits (Save/Cancel/error, toggle switches, the
"is this the signed-in account, and are they an admin on this server" check)
reused by 2+ of them.

`ownServerStatus`/`activeTab`/`adminsStatus`/`versionStatus` (and the RPCs that
fill in the latter two) stay here rather than in any one submodule -- they're
about loading the page's *subject* (which server, which tab, who its admins
are, what version it's running), not any one tab's editable content; `adminsStatus`/
`versionStatus` are fetched as soon as a server's known regardless of which tab
is active, even though only `AboutTab`'s `view` ever displays them.
-}

import Browser.Navigation
import Components.Pages.ServerInformationPage.AboutTab as AboutTab
import Components.Pages.ServerInformationPage.CdnTab as CdnTab
import Components.Pages.ServerInformationPage.ClusterTab as ClusterTab
import Components.Pages.ServerInformationPage.Common as Common
import Components.Pages.ServerInformationPage.ContactIntegrationsTab as ContactIntegrationsTab
import Components.Pages.ServerInformationPage.FederationTab as FederationTab
import Components.Pages.ServerInformationPage.MarketTab as MarketTab
import Components.Pages.ServerInformationPage.SettingsTab as SettingsTab
import Components.Pages.ServerInformationPage.ThemeTab as ThemeTab
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (GetServiceVersionResponse, GetUsersResponse, defaultGetUsersRequest)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Permission exposing (Permission(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Task
import UI.Classes exposing (classes)
import Url.Builder



-- MODEL


type alias Model =
    { targetHost : String
    , isSecure : Bool
    , navKey : Browser.Navigation.Key
    , path : String
    , ownServerStatus : OwnServerStatus
    , activeTab : Tab
    , adminsStatus : AboutTab.AdminsStatus
    , versionStatus : AboutTab.VersionStatus
    , aboutTab : AboutTab.Model
    , themeTab : ThemeTab.Model
    , settingsTab : SettingsTab.Model
    , federationTab : FederationTab.Model
    , cdnTab : CdnTab.Model
    , contactIntegrationsTab : ContactIntegrationsTab.Model
    , marketTab : MarketTab.Model
    , clusterTab : ClusterTab.Model
    }


type Msg
    = TabSelected Tab
    | GotOwnServerResult (Result Grpc.Error RellmServer)
    | AddServerClicked RellmServer
    | GotAdmins (Result Grpc.Error GetUsersResponse)
    | GotVersion (Result Grpc.Error GetServiceVersionResponse)
    | AboutTabMsg AboutTab.Msg
    | ThemeTabMsg ThemeTab.Msg
    | SettingsTabMsg SettingsTab.Msg
    | FederationTabMsg FederationTab.Msg
    | CdnTabMsg CdnTab.Msg
    | ContactIntegrationsTabMsg ContactIntegrationsTab.Msg
    | MarketTabMsg MarketTab.Msg
    | ClusterTabMsg ClusterTab.Msg
    | SharedMsg Shared.Msg


{-| Named `TabAbout`/etc. (not bare `AboutTab`/etc.) purely to avoid colliding with this module's
own `AboutTab`/`ThemeTab`/`SettingsTab`/`FederationTab`/`CdnTab` submodule aliases -- those are used
qualified (`AboutTab.Model`, `AboutTab.view`, ...) everywhere else in this file.
-}
type Tab
    = TabAbout
    | TabTheme
    | TabSettings
    | TabFederation
    | TabCdn
    | TabContactIntegrations
    | TabMarket
    | TabCluster


{-| `Tab`'s URL-facing form for the `tab` query param (see `pushTabUrl`) -- lowercase, mirroring
`Components.Pages.PostsPage.postContextParam`. `TabAbout` is the default and is never written out
(see `pushTabUrl`), but is included here for `tabFromParam`'s sake.
-}
tabParam : Tab -> String
tabParam tab =
    case tab of
        TabAbout ->
            "about"

        TabTheme ->
            "theme"

        TabSettings ->
            "settings"

        TabFederation ->
            "federation"

        TabCdn ->
            "cdn"

        TabContactIntegrations ->
            "contact-integrations"

        TabMarket ->
            "market"

        TabCluster ->
            "cluster"


{-| Case-insensitive inverse of `tabParam`, mirroring
`Components.Pages.PostsPage.postContextFromParam`. Any unrecognized value (e.g. a hand-edited link)
round-trips back to `Nothing`, falling back to `TabAbout` in `init`.
-}
tabFromParam : String -> Maybe Tab
tabFromParam param =
    case String.toLower param of
        "about" ->
            Just TabAbout

        "theme" ->
            Just TabTheme

        "settings" ->
            Just TabSettings

        "federation" ->
            Just TabFederation

        "cdn" ->
            Just TabCdn

        "contact-integrations" ->
            Just TabContactIntegrations

        "market" ->
            Just TabMarket

        "cluster" ->
            Just TabCluster

        _ ->
            Nothing


{-| This page's own probe of the server, kept entirely separate from
`Shared.AccountsPanel.Model.servers` -- see the module doc. Irrelevant (`OwnServerNotNeeded`)
whenever the server's already known.
-}
type OwnServerStatus
    = OwnServerNotNeeded
    | LoadingOwnServer
    | OwnServerLoaded RellmServer
    | OwnServerFailed String


{-| `pageIsSecure` is `Shared.AccountsPanel.RellmServers.isSecure req` (`Pages.About`) or parsed straight out of
the route (`Pages.Server.ServerIdentifier_`'s `[http|https]:hostname` segment) -- needed for the
own-probe fallback (see `RellmServers.connectToRellmServer`), but not otherwise derivable from
`Shared.Model` alone. `navKey`/`path`, from the calling page's own `Request`, are what let
`TabSelected` persist the active tab as a `tab` URL query param (see `pushTabUrl`), mirroring
`Components.Pages.PostsPage.init`'s own `navKey`/`path` (there, for `search_text`/`context`) --
exactly, since every caller's `Request.key`/`Request.url.path` fit this regardless of which
page-specific `Gen.Params.*` type they're parameterized over. `query`, that same `Request`'s
already-parsed `.query`, seeds `activeTab` back out of the URL on load, so a shared/reloaded link
reopens on the same tab.
-}
init : Shared.Model -> Bool -> String -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init shared pageIsSecure targetHost navKey path query =
    let
        model0 : Model
        model0 =
            { targetHost = targetHost
            , isSecure = pageIsSecure
            , navKey = navKey
            , path = path
            , ownServerStatus = LoadingOwnServer
            , activeTab = Dict.get "tab" query |> Maybe.andThen tabFromParam |> Maybe.withDefault TabAbout
            , adminsStatus = AboutTab.AdminsNotLoaded
            , versionStatus = AboutTab.VersionNotLoaded
            , aboutTab = AboutTab.init
            , themeTab = ThemeTab.init
            , settingsTab = SettingsTab.init
            , federationTab = FederationTab.init
            , cdnTab = CdnTab.init
            , contactIntegrationsTab = ContactIntegrationsTab.init
            , marketTab = MarketTab.init
            , clusterTab = ClusterTab.init
            }

        ( fetchedModel, fetchEffect ) =
            case knownConnectedServer shared targetHost of
                Just server ->
                    let
                        newModel : Model
                        newModel =
                            { model0 | ownServerStatus = OwnServerNotNeeded, adminsStatus = AboutTab.LoadingAdmins, versionStatus = AboutTab.LoadingVersion }

                        ( clusterTabModel, clusterTabEffect ) =
                            activateClusterTab shared newModel

                        ( contactIntegrationsTabModel, contactIntegrationsTabEffect ) =
                            activateContactIntegrationsTab shared newModel

                        ( marketTabModel, marketTabEffect ) =
                            activateMarketTab shared newModel
                    in
                    ( { newModel | clusterTab = clusterTabModel, contactIntegrationsTab = contactIntegrationsTabModel, marketTab = marketTabModel }
                    , Effect.batch [ fetchAdmins server, fetchVersion server, clusterTabEffect, contactIntegrationsTabEffect, marketTabEffect ]
                    )

                Nothing ->
                    -- Not connected yet -- `activateClusterTab` has to wait for
                    -- `GotOwnServerResult`'s own success branch, same reasoning as
                    -- `fetchAdmins`/`fetchVersion` not firing here either. Firing it right here
                    -- instead (a deep link straight to `?tab=cluster` looks exactly like this
                    -- branch on first load) raced ahead of the connection actually completing and
                    -- failed with a `Grpc.NetworkError` every time -- see `ClusterTab`'s own doc.
                    ( model0
                    , RellmServers.connectToRellmServer pageIsSecure targetHost
                        |> Task.attempt GotOwnServerResult
                        |> Effect.fromCmd
                    )
    in
    ( fetchedModel
      -- Closes the Accounts Panel if it happened to be open -- landing on
      -- either of this component's pages (`Pages.About`/
      -- `Pages.Server.ServerIdentifier_`) always shows the info it'd
      -- otherwise duplicate, so leaving the panel open reads as redundant.
    , Effect.batch [ fetchEffect, setBreadcrumbsHost shared fetchedModel ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map ThemeTabMsg (ThemeTab.subscriptions model.themeTab)
        , Sub.map FederationTabMsg (FederationTab.subscriptions model.federationTab)
        ]



-- UPDATE


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page into `update`'s
`SharedMsg` branch -- see `Pages.Post.PostId_.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            updateInner shared msg model
    in
    ( newModel, Effect.batch [ effect, setBreadcrumbsHost shared newModel ] )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        TabSelected tab ->
            let
                newModel : Model
                newModel =
                    { model | activeTab = tab }

                ( clusterTabModel, clusterTabEffect ) =
                    activateClusterTab shared newModel

                ( contactIntegrationsTabModel, contactIntegrationsTabEffect ) =
                    activateContactIntegrationsTab shared newModel

                ( marketTabModel, marketTabEffect ) =
                    activateMarketTab shared newModel
            in
            ( { newModel | clusterTab = clusterTabModel, contactIntegrationsTab = contactIntegrationsTabModel, marketTab = marketTabModel }
            , Effect.batch [ pushTabUrl newModel, clusterTabEffect, contactIntegrationsTabEffect, marketTabEffect ]
            )

        GotOwnServerResult (Ok server) ->
            let
                newModel : Model
                newModel =
                    { model | ownServerStatus = OwnServerLoaded server, adminsStatus = AboutTab.LoadingAdmins, versionStatus = AboutTab.LoadingVersion }

                ( clusterTabModel, clusterTabEffect ) =
                    activateClusterTab shared newModel

                ( contactIntegrationsTabModel, contactIntegrationsTabEffect ) =
                    activateContactIntegrationsTab shared newModel

                ( marketTabModel, marketTabEffect ) =
                    activateMarketTab shared newModel
            in
            ( { newModel | clusterTab = clusterTabModel, contactIntegrationsTab = contactIntegrationsTabModel, marketTab = marketTabModel }
            , Effect.batch [ fetchAdmins server, fetchVersion server, clusterTabEffect, contactIntegrationsTabEffect, marketTabEffect ]
            )

        GotOwnServerResult (Err err) ->
            ( { model | ownServerStatus = OwnServerFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        AddServerClicked server ->
            ( model, Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ServerConnected server)) )

        GotAdmins (Ok response) ->
            ( { model | adminsStatus = AboutTab.AdminsLoaded (List.filter (\user -> List.member ADMIN user.permissions) response.users) }
            , Effect.none
            )

        GotAdmins (Err _) ->
            ( { model | adminsStatus = AboutTab.AdminsFailed }, Effect.none )

        GotVersion (Ok response) ->
            ( { model | versionStatus = AboutTab.VersionLoaded response.version }, Effect.none )

        GotVersion (Err _) ->
            ( { model | versionStatus = AboutTab.VersionFailed }, Effect.none )

        AboutTabMsg subMsg ->
            AboutTab.update shared model.targetHost subMsg model.aboutTab
                |> Tuple.mapFirst (\subModel -> { model | aboutTab = subModel })
                |> Tuple.mapSecond (Effect.map AboutTabMsg)

        ThemeTabMsg subMsg ->
            ThemeTab.update shared model.targetHost (effectiveServer shared model) subMsg model.themeTab
                |> Tuple.mapFirst (\subModel -> { model | themeTab = subModel })
                |> Tuple.mapSecond (Effect.map ThemeTabMsg)

        SettingsTabMsg subMsg ->
            SettingsTab.update shared model.targetHost (effectiveServer shared model) subMsg model.settingsTab
                |> Tuple.mapFirst (\subModel -> { model | settingsTab = subModel })
                |> Tuple.mapSecond (Effect.map SettingsTabMsg)

        FederationTabMsg subMsg ->
            FederationTab.update shared model.targetHost model.isSecure (effectiveServer shared model) subMsg model.federationTab
                |> Tuple.mapFirst (\subModel -> { model | federationTab = subModel })
                |> Tuple.mapSecond (Effect.map FederationTabMsg)

        CdnTabMsg subMsg ->
            CdnTab.update shared model.targetHost (effectiveServer shared model) subMsg model.cdnTab
                |> Tuple.mapFirst (\subModel -> { model | cdnTab = subModel })
                |> Tuple.mapSecond (Effect.map CdnTabMsg)

        ContactIntegrationsTabMsg subMsg ->
            ContactIntegrationsTab.update shared model.targetHost (effectiveServer shared model) subMsg model.contactIntegrationsTab
                |> Tuple.mapFirst (\subModel -> { model | contactIntegrationsTab = subModel })
                |> Tuple.mapSecond (Effect.map ContactIntegrationsTabMsg)

        MarketTabMsg subMsg ->
            MarketTab.update shared model.targetHost subMsg model.marketTab
                |> Tuple.mapFirst (\subModel -> { model | marketTab = subModel })
                |> Tuple.mapSecond (Effect.map MarketTabMsg)

        ClusterTabMsg subMsg ->
            ClusterTab.update shared model.targetHost subMsg model.clusterTab
                |> Tuple.mapFirst (\subModel -> { model | clusterTab = subModel })
                |> Tuple.mapSecond (Effect.map ClusterTabMsg)

        SharedMsg subMsg ->
            let
                newModel : Model
                newModel =
                    { model
                        | aboutTab = AboutTab.applySharedMsg subMsg model.aboutTab
                        , themeTab = ThemeTab.applySharedMsg subMsg model.themeTab
                    }

                ( clusterTabModel, clusterTabEffect ) =
                    activateClusterTab shared newModel

                ( contactIntegrationsTabModel, contactIntegrationsTabEffect ) =
                    activateContactIntegrationsTab shared newModel

                ( marketTabModel, marketTabEffect ) =
                    activateMarketTab shared newModel
            in
            ( { newModel | clusterTab = clusterTabModel, contactIntegrationsTab = contactIntegrationsTabModel, marketTab = marketTabModel }
            , Effect.batch [ Effect.fromShared subMsg, clusterTabEffect, contactIntegrationsTabEffect, marketTabEffect ]
            )


{-| `Shared.AccountsPanel`'s cached entry for `targetHost`, if it's both known _and_ actually
connected (see `RellmServers.knownConnectedRellmServer`) -- a known-but-disconnected entry is treated
the same as not known at all, so this page falls back to its own probe (just like a never-added
host) rather than trying to show configuration/admins/version for a server it can't currently reach.
-}
knownConnectedServer : Shared.Model -> String -> Maybe RellmServer
knownConnectedServer shared targetHost =
    RellmServers.knownConnectedRellmServer shared.accounts.servers targetHost


{-| The `Server` to actually show details for -- whichever the app already knows about and is
connected to (from `Shared.AccountsPanel`, if this server's been added to Accounts & Servers
already), falling back to this page's own probe (`ownServerStatus`) otherwise.
-}
effectiveServer : Shared.Model -> Model -> Maybe RellmServer
effectiveServer shared model =
    case knownConnectedServer shared model.targetHost of
        Just server ->
            Just server

        Nothing ->
            case model.ownServerStatus of
                OwnServerLoaded server ->
                    Just server

                _ ->
                    Nothing


{-| Fires `ClusterTab.activated`'s authenticated fetch whenever `model.activeTab` is already
`TabCluster` -- called everywhere this page's own connectivity state settles (`init`'s
already-known-connected branch, `GotOwnServerResult`'s own-probe success, and `TabSelected`), never
unconditionally at `init` itself. `ClusterTab.activated`'s own fetch resolves `model.targetHost`
against `Shared.AccountsPanel`'s live connection state (see `ClusterTab`'s own doc); firing it
before that connection has actually finished being established races ahead of it and fails with a
`Grpc.NetworkError` -- exactly what happened when this used to fire unconditionally in `init`,
breaking a fresh page load landing straight on `?tab=cluster` (though never a same-session click,
since `effectiveServer` is already resolved by the time any tab is clickable at all).
-}
activateClusterTab : Shared.Model -> Model -> ( ClusterTab.Model, Effect Msg )
activateClusterTab shared model =
    if model.activeTab == TabCluster then
        ClusterTab.update shared model.targetHost ClusterTab.activated model.clusterTab
            |> Tuple.mapSecond (Effect.map ClusterTabMsg)

    else
        ( model.clusterTab, Effect.none )


{-| Same as `activateClusterTab`, for `ContactIntegrationsTab.activated` -- `twilio_config`/
`bird_config`/`preferred_verification_apis` are admin-only-serialized the same way
`cluster_resources` is (see `ContactIntegrationsTab`'s own doc), so this tab needs the identical
"fire from everywhere connectivity could have settled" treatment, called from the exact same sites.
-}
activateContactIntegrationsTab : Shared.Model -> Model -> ( ContactIntegrationsTab.Model, Effect Msg )
activateContactIntegrationsTab shared model =
    if model.activeTab == TabContactIntegrations then
        ContactIntegrationsTab.update shared model.targetHost (effectiveServer shared model) ContactIntegrationsTab.activated model.contactIntegrationsTab
            |> Tuple.mapSecond (Effect.map ContactIntegrationsTabMsg)

    else
        ( model.contactIntegrationsTab, Effect.none )


{-| Same as `activateClusterTab`, for `MarketTab.activated` -- `stripe_config` is admin-only-
serialized the same way `cluster_resources` is (see `MarketTab`'s own doc), so this tab needs the
identical "fire from everywhere connectivity could have settled" treatment, called from the exact
same sites.
-}
activateMarketTab : Shared.Model -> Model -> ( MarketTab.Model, Effect Msg )
activateMarketTab shared model =
    if model.activeTab == TabMarket then
        MarketTab.update shared model.targetHost MarketTab.activated model.marketTab
            |> Tuple.mapSecond (Effect.map MarketTabMsg)

    else
        ( model.marketTab, Effect.none )


isKnownServer : Shared.Model -> Model -> Bool
isKnownServer shared model =
    knownConnectedServer shared model.targetHost /= Nothing


{-| `model.targetHost`/`isSecure` reassembled into the `[http|https]:hostname` form
`Pages.Server.ServerIdentifier_`'s route uses -- just for error messages here (see `view`'s
`OwnServerFailed` branch); this module has no route of its own to round-trip through.
-}
identifierText : Model -> String
identifierText model =
    (if model.isSecure then
        "https:"

     else
        "http:"
    )
        ++ model.targetHost


{-| Keeps `Shared.Breadcrumbs` pointed at this page's own `FromServerHost targetHost` -- mirrors
`Components.Pages.UserProfilePage.setBreadcrumbsHost` (reissued after every `update`, a no-op once
already in sync via the same equality check), so the trail identifies this server both on the very
first paint and across any later host change (e.g. `GotOwnServerResult` resolving the own-probe).
-}
setBreadcrumbsHost : Shared.Model -> Model -> Effect Msg
setBreadcrumbsHost shared model =
    if shared.breadcrumbs.root == Just (Breadcrumbs.FromServerHost model.targetHost) then
        Effect.none

    else
        Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost model.targetHost) model.targetHost []))


{-| Persists `model.activeTab` to the URL as a `tab` query param, via `replaceUrl` (not `pushUrl` --
switching tabs shouldn't spam browser history with one entry per click). Omitted entirely at the
default (`TabAbout`), so the common case keeps a clean URL. Mirrors
`Components.Pages.PostsPage.pushSearchUrl` exactly, just over a single `Tab` param instead of
`search_text`/`context`.
-}
pushTabUrl : Model -> Effect Msg
pushTabUrl model =
    let
        tabParams : List Url.Builder.QueryParameter
        tabParams =
            if model.activeTab == TabAbout then
                []

            else
                [ Url.Builder.string "tab" (tabParam model.activeTab) ]
    in
    Browser.Navigation.replaceUrl model.navKey (model.path ++ Url.Builder.toQuery tabParams)
        |> Effect.fromCmd


fetchAdmins : RellmServer -> Effect Msg
fetchAdmins server =
    Grpc.new Rellm.getUsers defaultGetUsersRequest
        |> Grpc.setHost (RellmServers.rellmServerUrl server)
        |> Grpc.toTask
        |> Task.attempt GotAdmins
        |> Effect.fromCmd


fetchVersion : RellmServer -> Effect Msg
fetchVersion server =
    Grpc.new Rellm.getServiceVersion {}
        |> Grpc.setHost (RellmServers.rellmServerUrl server)
        |> Grpc.toTask
        |> Task.attempt GotVersion
        |> Effect.fromCmd



-- VIEW


{-| Just the subtitle -- the server's own name once known, else its `targetHost` -- for the calling
page's own `UI.pageTitle`.
-}
titleFor : Shared.Model -> Model -> String
titleFor shared model =
    case effectiveServer shared model of
        Just server ->
            (RellmServers.brandingOf server).name

        Nothing ->
            model.targetHost


view : Shared.Model -> Model -> Html Msg
view shared model =
    case effectiveServer shared model of
        Just server ->
            div [ class "server-details" ]
                [ addServerButton shared model server
                , tabBar shared model
                , tabContent shared model server
                ]

        Nothing ->
            case model.ownServerStatus of
                LoadingOwnServer ->
                    p [ class "server-details-loading" ] [ text ("Connecting to " ++ model.targetHost ++ "…") ]

                OwnServerFailed err ->
                    div [ class "server-details-error" ]
                        [ p [] [ text ("Couldn't find a Rellm server at " ++ identifierText model ++ ".") ]
                        , p [] [ text err ]
                        ]

                _ ->
                    text ""


addServerButton : Shared.Model -> Model -> RellmServer -> Html Msg
addServerButton shared model server =
    if isKnownServer shared model then
        text ""

    else
        div [ class "server-details-add" ]
            [ p [] [ text "This server hasn't been added to your Accounts & Servers yet -- these details are just a preview." ]
            , button [ class "server-details-add-button", onClick (AddServerClicked server) ] [ text ("Add " ++ model.targetHost) ]
            ]


{-| `TabCluster` only appears for a logged-in admin -- `cluster_resources` is stripped from
`GetServerConfiguration` entirely for anyone else (see `ClusterTab`'s own doc), so there'd be
nothing to show a non-admin there.
-}
tabBar : Shared.Model -> Model -> Html Msg
tabBar shared model =
    div [ class "server-details-tab-bar" ]
        (List.map (tabButton model)
            ([ ( TabAbout, "About" )
             , ( TabTheme, "Theme" )
             , ( TabSettings, "Settings" )
             , ( TabFederation, "Federation" )
             , ( TabCdn, "CDN" )
             ]
                ++ (if Common.adminAccountFor shared model.targetHost /= Nothing then
                        [ ( TabContactIntegrations, "Contact Integrations" ), ( TabMarket, "Market" ), ( TabCluster, "Cluster" ) ]

                    else
                        []
                   )
            )
        )


tabButton : Model -> ( Tab, String ) -> Html Msg
tabButton model ( tab, label_ ) =
    button
        [ classes
            ("server-details-tab"
                :: (if model.activeTab == tab then
                        [ "selected" ]

                    else
                        []
                   )
            )
        , onClick (TabSelected tab)
        ]
        [ text label_ ]


tabContent : Shared.Model -> Model -> RellmServer -> Html Msg
tabContent shared model server =
    let
        maybeAdminAccount : Maybe RellmAccount
        maybeAdminAccount =
            Common.adminAccountFor shared model.targetHost
    in
    case model.activeTab of
        TabAbout ->
            Html.map AboutTabMsg (AboutTab.view shared server maybeAdminAccount model.adminsStatus model.versionStatus model.aboutTab)

        TabTheme ->
            Html.map ThemeTabMsg (ThemeTab.view shared server maybeAdminAccount model.themeTab)

        TabSettings ->
            Html.map SettingsTabMsg (SettingsTab.view server maybeAdminAccount model.settingsTab)

        TabFederation ->
            Html.map FederationTabMsg (FederationTab.view shared server maybeAdminAccount model.federationTab)

        TabCdn ->
            Html.map CdnTabMsg (CdnTab.view server maybeAdminAccount model.cdnTab)

        TabContactIntegrations ->
            Html.map ContactIntegrationsTabMsg (ContactIntegrationsTab.view server maybeAdminAccount model.contactIntegrationsTab)

        TabMarket ->
            Html.map MarketTabMsg (MarketTab.view maybeAdminAccount model.marketTab)

        TabCluster ->
            Html.map ClusterTabMsg (ClusterTab.view shared server maybeAdminAccount model.clusterTab)
