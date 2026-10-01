module Support.RellmServerFactory exposing (connected, connectedWithPushKey, disconnected)

{-| Minimal `RellmServer` builders for tests that only care about a server's host and (optionally)
its advertised Web Push VAPID public key -- `Proto.Rellm`'s generated `defaultServerConfiguration`
is the factory for everything else, same approach as `Support.PostFactory`.
-}

import Proto.Rellm exposing (defaultServerConfiguration)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)


{-| Connected, with no `WebPushConfig` at all (a server that hasn't configured push).
-}
connected : String -> RellmServer
connected frontendHost =
    withConfig frontendHost Nothing


{-| Connected, advertising `publicVapidKey` in its `WebPushConfig`.
-}
connectedWithPushKey : String -> String -> RellmServer
connectedWithPushKey frontendHost publicVapidKey =
    withConfig frontendHost (Just { publicVapidKey = publicVapidKey, privateVapidKey = "" })


{-| Known but not connected -- `RellmServer.connected == Nothing`, so no configuration (and no
push key) is known yet.
-}
disconnected : String -> RellmServer
disconnected frontendHost =
    { frontendHost = frontendHost
    , enabled = True
    , connected = Nothing
    , sortOrder = 0
    }


withConfig : String -> Maybe { publicVapidKey : String, privateVapidKey : String } -> RellmServer
withConfig frontendHost webPushConfig =
    { frontendHost = frontendHost
    , enabled = True
    , connected =
        Just
            { backendHost = frontendHost
            , port_ = 443
            , tls = True
            , configuration = { defaultServerConfiguration | webPushConfig = webPushConfig }
            , branding = RellmServers.brandingFor [] frontendHost
            }
    , sortOrder = 0
    }
