module Components.ServerDependentView exposing (ConnectStatus(..), availableServer, hostLabel, view)

{-| A view for content that belongs to a specific server (by hostname) which
the app might not actually know about yet -- e.g. a post linked from another
Rellm server (see `Pages.Post.PostId_`). Resolves the hostname against the
app's known servers and either renders `render` with what it finds (the
matching `Server`, and whichever of its accounts is currently enabled, if
any), or shows a prompt instead -- to connect to the server, if it isn't known
at all, or noting that it's disabled, if it's known but the user has toggled
it off (see `Shared.AccountsPanel`'s `Server.enabled`) -- either way, `render`
just isn't called, so the caller never has to itself branch on "is this
server actually usable right now".

Connecting is entirely up to the caller (`onConnectClicked`/`connectStatus`),
typically by kicking off `Shared.RellmServers.connectToRellmServer` and, once it
resolves, dispatching `Shared.AccountsPanel.ServerConnected` to register it
(and then whatever the caller actually wanted the server for -- e.g. fetching
the post it was after all along). Re-enabling a disabled server is simpler --
just `AccountsPanel.ToggleServerEnabled` -- so `onEnableClicked` is a plain
`msg` rather than needing a status to track, unlike `onConnectClicked`.

-}

import Dict exposing (Dict)
import Html exposing (Html, button, div, p, span, text)
import Html.Attributes exposing (attribute, class, disabled, title)
import Html.Events exposing (onClick)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)


{-| The status of a caller-driven attempt to connect to the not-yet-known
server -- `Components.ServerDependentView` only displays this; it doesn't
track it itself, so it stays in sync with whatever else the caller does once
connecting succeeds (see the module doc).
-}
type ConnectStatus
    = NotConnected
    | Connecting
    | ConnectFailed String


view :
    { hostname : String
    , servers : List RellmServer
    , accounts : List RellmAccount
    , connectStatus : ConnectStatus

    -- `AccountsPanel.recommendedServerConnections`: previews of servers the user hasn't added, for the
    -- Add button (see `hostLabel`). The caller asks for the preview itself, with
    -- `AccountsPanel.EnsureServerPreviews [ hostname ]` when it opens.
    , previews : Dict String RellmServer
    , onConnectClicked : msg
    , onEnableClicked : msg
    }
    -> (RellmServer -> Maybe RellmAccount -> Html msg)
    -> Html msg
view config render =
    case RellmServers.rellmServerForHost config.servers config.hostname of
        Just server ->
            if server.enabled then
                render server (RellmAccounts.enabledRellmAccountForServer config.accounts config.hostname)

            else
                div [ class "server-dependent-prompt" ]
                    [ p [] [ text (config.hostname ++ " is disabled. Re-enable it in your Servers to see it.") ]
                    , button
                        [ class "server-action-button"
                        , onClick config.onEnableClicked
                        , title ("Enable " ++ config.hostname)
                        ]
                        [ text "Enable ", hostLabel server ]
                    ]

        Nothing ->
            let
                connecting : Bool
                connecting =
                    config.connectStatus == Connecting
            in
            div [ class "server-dependent-prompt" ]
                [ p [] [ text ("This is on " ++ config.hostname ++ ", which isn't one of your servers yet.") ]
                , button
                    [ class "server-action-button"
                    , onClick config.onConnectClicked
                    , disabled connecting
                    , title ("Add " ++ config.hostname)
                    ]
                    (if connecting then
                        [ text "Connecting…" ]

                     else
                        [ text "Add ", hostLabel (RellmServers.previewOf config.servers config.previews config.hostname) ]
                    )
                , case config.connectStatus of
                    ConnectFailed err ->
                        p [ class "server-dependent-error" ] [ text err ]

                    _ ->
                        text ""
                ]


{-| A server's logo with its name split over one or two rows beside it, like the nav's Home button -- what
the "Enable <server>" / "Add <server>" buttons (here, and `Shared.StarredPanel`'s) show in place of the bare
hostname. Pass `RellmServers.previewOf`'s result: it's the user's own server's branding if it has any, else the
preview loaded for it, else just the host.
-}
hostLabel : RellmServer -> Html msg
hostLabel server =
    span [ class "server-action-preview", attribute "aria-label" server.frontendHost ]
        [ RellmServers.rellmServerNameAndLogo server RellmServers.HorizontalServerLogo ]


{-| `hostname` resolved to its `Server`, but only if it's both known and
`enabled` -- `Nothing` either way otherwise. The same "is this content's
server actually usable right now" condition `view` itself gates on above,
exposed for callers (e.g. `Shared.StarredPanel`'s fetching) that need to
gate something other than rendering on it, without duplicating the `.enabled`
check themselves.
-}
availableServer : List RellmServer -> String -> Maybe RellmServer
availableServer servers hostname =
    RellmServers.rellmServerForHost servers hostname
        |> Maybe.andThen
            (\server ->
                if server.enabled then
                    Just server

                else
                    Nothing
            )
