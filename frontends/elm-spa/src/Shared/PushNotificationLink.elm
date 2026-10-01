module Shared.PushNotificationLink exposing (toInAppPath)

{-| Turns the absolute deep link a push notification carries (`PushPayload.url`, built by
`backend/src/web_push/mod.rs`'s `notification_url` as `https://<frontend_host>/messages?
messaging_group=<id>#message-<id>`) into a path this running app can route to itself.

Needed once one browser push subscription is shared by several servers (see
`AccountsPanel.canUsePushNotifications`): a notification from server B can be clicked while this
PWA is installed from server A, and `WindowClient.navigate()` can't cross origins, so
`service-worker.js` hands the URL to the app instead (`Ports.pushNotificationClicked`) and the app
routes within itself. The ids in that URL belong to _B_, so they need `Components.Messages`'
`id@host` suffix (`groupRouteId`) to resolve against the right server rather than
`mainFrontendHost`.

-}

import Components.Messages as Messages
import Url


{-| `mainFrontendHost` is the host the app treats as "local" (ids with no `@host` suffix resolve to
it -- see `Messages.parseGroupRouteId`). Returns the in-app path + query + fragment (no origin, no
base path), or `Nothing` if `rawUrl` isn't an absolute http(s) URL.

Only the `messaging_group`/`message` query values are rewritten, and only when the notification's
own host differs from `mainFrontendHost` and the value doesn't already carry an `@host` suffix.
Everything else (path, other params, fragment) passes through untouched.
-}
toInAppPath : String -> String -> Maybe String
toInAppPath mainFrontendHost rawUrl =
    Url.fromString rawUrl
        |> Maybe.map
            (\url ->
                let
                    notificationHost : String
                    notificationHost =
                        case url.port_ of
                            Just port_ ->
                                url.host ++ ":" ++ String.fromInt port_

                            Nothing ->
                                url.host

                    rewriteParam : String -> String
                    rewriteParam pair =
                        case String.split "=" pair of
                            [ key, value ] ->
                                if (key == "messaging_group" || key == "message") && not (String.contains "@" value) then
                                    key ++ "=" ++ Messages.groupRouteId mainFrontendHost notificationHost value

                                else
                                    pair

                            _ ->
                                pair
                in
                url.path
                    ++ (url.query
                            |> Maybe.map (\query -> "?" ++ (query |> String.split "&" |> List.map rewriteParam |> String.join "&"))
                            |> Maybe.withDefault ""
                       )
                    ++ (url.fragment |> Maybe.map (\fragment -> "#" ++ fragment) |> Maybe.withDefault "")
            )
